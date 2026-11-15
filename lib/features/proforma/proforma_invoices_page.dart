import 'dart:ui';
import 'dart:io';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/clearing_agent_model.dart';
import 'proforma_invoice_model.dart';
import 'proforma_invoice_dao.dart';
import 'proforma_invoice_cubit.dart';
import 'proforma_invoice_pdf_service.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ProformaInvoicesPage extends StatefulWidget {
  const ProformaInvoicesPage({super.key});

  @override
  State<ProformaInvoicesPage> createState() => _ProformaInvoicesPageState();
}

class _ProformaInvoicesPageState extends State<ProformaInvoicesPage> {
  final _searchController = TextEditingController();
  DateTime? _selectedFromDate;
  DateTime? _selectedToDate;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProformaInvoiceCubit>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        body: Column(
          children: [
            _buildHeader(),
            if (_showFilters) _buildFilters(),
            Expanded(
              child: BlocConsumer<ProformaInvoiceCubit, ProformaInvoiceState>(
                listener: (context, state) {
                  if (state is ProformaInvoiceOperationSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(state.message),
                          backgroundColor: AppTheme.success,
                          duration: const Duration(seconds: 3)),
                    );
                    _applyFilters();
                  } else if (state is ProformaInvoiceError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(state.message),
                          backgroundColor: AppTheme.danger,
                          duration: const Duration(seconds: 3)),
                    );
                  }
                },
                builder: (context, state) {
                  if (state is ProformaInvoiceLoading) {
                    return const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.primary));
                  }
                  if (state is ProformaInvoiceListLoaded) {
                    if (state.invoices.isEmpty) return _buildEmptyState();
                    return _buildDataTable(state.invoices);
                  }
                  return _buildEmptyState();
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(null),
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('فاتورة مبدئية جديدة',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 16,
              left: 20,
              right: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            border: Border(
                bottom: BorderSide(
                    color: isDark
                        ? AppTheme.glassBorder.withAlpha(50)
                        : const Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_outlined,
                    color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('الفواتير المبدئية',
                    style: TextStyle(
                        color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ),
              GestureDetector(
                onTap: () => setState(() => _showFilters = !_showFilters),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.primary.withAlpha(20)
                          : const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark
                              ? AppTheme.primary.withAlpha(60)
                              : const Color(0xFFBAE6FD))),
                  child: const Icon(Icons.filter_list,
                      color: AppTheme.primary, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              _buildIconButton(Icons.refresh_rounded, () {
                _applyFilters();
              }),
              const SizedBox(width: 8),
              //_buildIconButton(Icons.table_chart_outlined, () => _exportExcel()),
              const SizedBox(width: 8),
              //_buildIconButton(Icons.picture_as_pdf_outlined, () => _exportPdfAll()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: isDark ? AppTheme.cardBg : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        child: Icon(icon,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
            size: 20),
      ),
    );
  }

  Widget _buildFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardBg.withAlpha(100) : Colors.white,
        border: Border(
            bottom: BorderSide(
                color: isDark
                    ? AppTheme.glassBorder.withAlpha(30)
                    : const Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                      color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    hintText: 'بحث برقم الفاتورة أو اسم العميل...',
                    hintStyle: TextStyle(
                        color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                        fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.search,
                        color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                        size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: isDark ? Colors.transparent : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                  ),
                  onSubmitted: (_) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _DateFilterField(
                  label: 'من تاريخ',
                  date: _selectedFromDate,
                  onChanged: (d) {
                    setState(() => _selectedFromDate = d);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 160,
                child: _DateFilterField(
                  label: 'إلى تاريخ',
                  date: _selectedToDate,
                  onChanged: (d) {
                    setState(() => _selectedToDate = d);
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _applyFilters() {
    context.read<ProformaInvoiceCubit>().load(
          search:
              _searchController.text.isNotEmpty ? _searchController.text : null,
          fromDate: _selectedFromDate != null
              ? '${_selectedFromDate!.year}-${_selectedFromDate!.month.toString().padLeft(2, '0')}-${_selectedFromDate!.day.toString().padLeft(2, '0')}'
              : null,
          toDate: _selectedToDate != null
              ? '${_selectedToDate!.year}-${_selectedToDate!.month.toString().padLeft(2, '0')}-${_selectedToDate!.day.toString().padLeft(2, '0')}'
              : null,
        );
  }

  Widget _buildDataTable(List<ProformaInvoiceModel> invoices) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget content = Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cyberSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? AppTheme.glassBorder.withAlpha(40)
                    : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
          ),
          child: Column(
            children: [
              _buildTableHeader(),
              ...invoices.asMap().entries.map((entry) =>
                  _buildTableRow(entry.key, entry.value, invoices.length)),
            ],
          ),
        );

        if (constraints.maxWidth < 900) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 900,
              child: content,
            ),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.primary.withAlpha(15) : const Color(0xFFF1F5F9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
            bottom: BorderSide(
                color: isDark
                    ? AppTheme.glassBorder.withAlpha(30)
                    : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text('رقم الفاتورة',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                  textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(
              flex: 2,
              child: Text('التاريخ',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                  textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(
              flex: 3,
              child: Text('العميل',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'))),
          const SizedBox(width: 8),
          Expanded(
              flex: 2,
              child: Text('الوجهة',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'))),
          const SizedBox(width: 8),
          Expanded(
              flex: 2,
              child: Text('الإجمالي',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                  textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(
              flex: 2,
              child: Text('إجراءات',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                  textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(int index, ProformaInvoiceModel invoice, int total) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final symbol = _currencySymbol(invoice.currency);
    final isLast = index == total - 1;
    final dateStr = invoice.invoiceDate != null
        ? '${invoice.invoiceDate!.year}-${invoice.invoiceDate!.month.toString().padLeft(2, '0')}-${invoice.invoiceDate!.day.toString().padLeft(2, '0')}'
        : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: !isDark && index % 2 == 1 ? const Color(0xFFF8FAFC) : Colors.transparent,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: isDark
                        ? AppTheme.glassBorder.withAlpha(30)
                        : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(invoice.invoiceNo,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                  textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(dateStr,
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(invoice.customerName ?? '—',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(invoice.country ?? '—',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
                '$symbol ${invoice.totalAmount.toStringAsFixed(2)}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRowAction(
                    Icons.edit_outlined, () => _openForm(invoice)),
                const SizedBox(width: 6),
                _buildRowAction(Icons.picture_as_pdf_outlined,
                    () => _generatePdf(invoice)),
                const SizedBox(width: 6),
                _buildRowAction(Icons.delete_outline, () => _delete(invoice),
                    color: AppTheme.danger),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowAction(IconData icon, VoidCallback onTap,
      {Color color = AppTheme.primary}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: color.withAlpha(isDark ? 15 : 25),
            borderRadius: BorderRadius.circular(8),
            border: isDark ? null : Border.all(color: color.withAlpha(50))),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              color: isDark ? AppTheme.textMuted : const Color(0xFF94A3B8),
              size: 64),
          const SizedBox(height: 16),
          Text('لا توجد فواتير مبدئية',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text('اضغط على + لإنشاء فاتورة مبدئية جديدة',
              style: TextStyle(
                  color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                  fontSize: 13,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  void _openForm(ProformaInvoiceModel? invoice) async {
    if (!mounted) return;
    if (invoice != null) {
      await context.push('/proforma-invoices/${invoice.id}/edit',
          extra: invoice);
    } else {
      await context.push('/proforma-invoices/new');
    }
    if (mounted) {
      context.read<ProformaInvoiceCubit>().load();
    }
  }

  void _generatePdf(ProformaInvoiceModel invoice) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('جاري إنشاء ملف PDF...'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2)),
    );
    try {
      final dao = ProformaInvoiceDao();
      final items = await dao.getItems(invoice.id);

      CustomerModel? customer;
      ClearingAgentModel? clearingAgent;
      try {
        if (invoice.customerId != null && invoice.customerId!.isNotEmpty) {
          final custData = await Supabase.instance.client
              .from('customers')
              .select()
              .eq('id', invoice.customerId!)
              .maybeSingle();
          if (custData != null) customer = CustomerModel.fromMap(custData);
        }
      } catch (_) {}
      try {
        if (invoice.clearingAgentId != null &&
            invoice.clearingAgentId!.isNotEmpty) {
          final agentData = await Supabase.instance.client
              .from('clearing_agents')
              .select()
              .eq('id', invoice.clearingAgentId!)
              .maybeSingle();
          if (agentData != null)
            clearingAgent = ClearingAgentModel.fromMap(agentData);
        }
      } catch (_) {}

      final doc = await ProformaInvoicePdfService.generate(invoice,
          items: items, customer: customer, clearingAgent: clearingAgent);
      final bytes = await doc.save();
      final dir = await FileHelper.getExportDirectory();
      final invoiceNo = invoice.invoiceNo.replaceAll('/', '-');
      final file = File('${dir.path}/proforma_$invoiceNo.pdf');
      await file.writeAsBytes(bytes);
      await Printing.sharePdf(
          bytes: bytes, filename: 'proforma_$invoiceNo.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم حفظ PDF في: ${file.path}'),
            backgroundColor: AppTheme.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _delete(ProformaInvoiceModel invoice) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        title:
            const Text('حذف الفاتورة', style: TextStyle(fontFamily: 'Cairo')),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: RichText(
            text: TextSpan(
              text: 'هل تريد حذف الفاتورة ',
              style: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textPrimary, fontSize: 16),
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      invoice.invoiceNo,
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ),
                const TextSpan(text: '؟'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) {
                context.read<ProformaInvoiceCubit>().delete(invoice.id);
              }
            },
            child: const Text('حذف', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }

  String _currencySymbol(String? currency) {
    switch (currency) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return 'ج.م';
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _exportExcel() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('جاري إنشاء ملف Excel...'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2)),
    );
    try {
      final dao = ProformaInvoiceDao();
      final allInvoices = await dao.getAll(
        searchQuery:
            _searchController.text.isNotEmpty ? _searchController.text : null,
        fromDate: _selectedFromDate != null ? _fmtDate(_selectedFromDate!) : null,
        toDate: _selectedToDate != null ? _fmtDate(_selectedToDate!) : null,
        limit: 10000,
      );
      if (allInvoices.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لا توجد فواتير للتصدير'),
              backgroundColor: AppTheme.warning),
        );
        return;
      }

      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['فواتير مبدئية'];

      const headerBg = '#FF1A237E';
      const headerFg = '#FFFFFFFF';
      const totalBg = '#FF263238';
      const totalFg = '#FFFFFFFF';

      final headers = [
        'التاريخ',
        'رقم الفاتورة',
        'العميل',
        'الوجهة',
        'رقم الحاوية',
        'البوليصة',
        'المحصول',
        'الكراتين',
        'الوزن الصافي',
        'الوزن الصافي/كرتونة',
        'السعر/كرتونة',
        'الاجمالي',
      ];

      for (var c = 0; c < headers.length; c++) {
        final cell = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(headers[c]);
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString(headerBg),
          fontColorHex: ExcelColor.fromHexString(headerFg),
          fontSize: 11,
        );
      }

      var r = 1;

      for (final invoice in allInvoices) {
        final items = await dao.getItems(invoice.id);
        final dateStr = invoice.invoiceDate != null
            ? _fmtDate(invoice.invoiceDate!)
            : '';
        final blOrAwb = invoice.transportMode == 'air'
            ? (invoice.dataLoggerNo ?? '')
            : (invoice.blNumber ?? '');

        if (items.isEmpty) {
          _setExcelRow(sheet, r, [
            dateStr,
            invoice.invoiceNo,
            invoice.customerName ?? '',
            invoice.country ?? '',
            invoice.containerNo ?? '',
            blOrAwb,
            '',
            '',
            '',
            '',
            '',
            '${invoice.totalAmount.toStringAsFixed(2)} ${invoice.currency ?? ''}',
          ]);
          r++;
          continue;
        }

        for (final item in items) {
          final netPerCtn =
              item.quantity > 0 ? (item.netWeight / item.quantity) : 0.0;
          _setExcelRow(sheet, r, [
            dateStr,
            invoice.invoiceNo,
            invoice.customerName ?? '',
            invoice.country ?? '',
            invoice.containerNo ?? '',
            blOrAwb,
            item.productName,
            item.quantity.toStringAsFixed(0),
            item.netWeight.toStringAsFixed(2),
            netPerCtn.toStringAsFixed(2),
            '${item.pricePerCarton.toStringAsFixed(2)} ${invoice.currency ?? ''}',
            '${item.totalAmount.toStringAsFixed(2)} ${invoice.currency ?? ''}',
          ]);
          r++;
        }
      }

      for (var c = 0; c < headers.length; c++) {
        sheet.setColumnWidth(c, 18);
      }
      sheet.setColumnWidth(1, 14);
      sheet.setColumnWidth(6, 25);

      final bytes = excel.encode();
      if (bytes == null) throw Exception('فشل إنشاء الملف');
      final dir = await FileHelper.getExportDirectory();
      final file = File(
          '${dir.path}/proforma_invoices_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم التصدير: ${file.path}'),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _setExcelRow(Sheet sheet, int row, List<String> values) {
    for (var c = 0; c < values.length; c++) {
      final cell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = TextCellValue(values[c]);
      cell.cellStyle = CellStyle(fontSize: 10);
    }
  }

  void _exportPdfAll() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('جاري إنشاء ملف PDF...'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2)),
    );
    try {
      final dao = ProformaInvoiceDao();
      final allInvoices = await dao.getAll(
        searchQuery:
            _searchController.text.isNotEmpty ? _searchController.text : null,
        fromDate: _selectedFromDate != null ? _fmtDate(_selectedFromDate!) : null,
        toDate: _selectedToDate != null ? _fmtDate(_selectedToDate!) : null,
        limit: 10000,
      );
      if (allInvoices.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لا توجد فواتير للتصدير'),
              backgroundColor: AppTheme.warning),
        );
        return;
      }
      for (final inv in allInvoices) {
        _generatePdf(inv);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
      );
    }
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
              colorScheme: isDark
                  ? const ColorScheme.dark(primary: AppTheme.primary)
                  : const ColorScheme.light(primary: AppTheme.primary),
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
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
          isDense: true,
          filled: true,
          fillColor: isDark ? Colors.transparent : const Color(0xFFF8FAFC),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
          suffixIcon: date != null
              ? GestureDetector(
                  onTap: () => onChanged(null),
                  child: Icon(Icons.close,
                      size: 16,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                )
              : Icon(Icons.calendar_today,
                  size: 14,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
        ),
        child: Text(
          date != null
              ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
              : '',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}
