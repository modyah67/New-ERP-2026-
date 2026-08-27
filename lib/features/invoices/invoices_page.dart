import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../core/router.dart';
import '../../data/models/invoice_model.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'invoice_cubit.dart';
import 'invoice_state.dart';
import 'invoice_form_page.dart';
import 'pdf_service.dart';

class InvoicesPage extends StatelessWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<InvoiceCubit>();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, controller),
            const SizedBox(height: 20),
            _buildSearchBar(context, controller),
            const SizedBox(height: 16),
            Expanded(child: _buildTable(context, controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, InvoiceCubit controller) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
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
              const Text('الفواتير', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              BlocBuilder<InvoiceCubit, InvoiceState>(
                builder: (context, state) {
                  final count = state is InvoiceLoaded ? state.invoices.length : 0;
                  return Text(
                    '$count فاتورة',
                    style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                  );
                },
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'تحديث',
            onPressed: controller.loadAll,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('فاتورة جديدة'),
            onPressed: () async {
              await controller.prepareNewInvoice();
              context.push('/invoices/new');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, InvoiceCubit controller) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            onChanged: controller.onSearchChanged,
            decoration: InputDecoration(
              hintText: 'بحث برقم الفاتورة أو اسم العميل...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: BlocBuilder<InvoiceCubit, InvoiceState>(
                builder: (context, state) {
                  final q = state is InvoiceLoaded ? state.searchQuery : '';
                  if (q.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => controller.onSearchChanged(''),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        BlocBuilder<InvoiceCubit, InvoiceState>(
          builder: (context, state) {
            final fromDate = state is InvoiceLoaded ? state.fromDate : null;
            final toDate = state is InvoiceLoaded ? state.toDate : null;
            return Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => controller.pickFromDate(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          fromDate == null
                              ? 'من تاريخ'
                              : AppUtils.formatDate(fromDate),
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        ),
                      ]),
                    ),
                  ),
                  const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                  InkWell(
                    onTap: () => controller.pickToDate(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          toDate == null
                              ? 'إلى تاريخ'
                              : AppUtils.formatDate(toDate),
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        ),
                      ]),
                    ),
                  ),
                  if (fromDate != null || toDate != null) ...[
                    const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: AppTheme.danger),
                      onPressed: controller.clearDateFilter,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ]
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, InvoiceCubit controller) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: BlocBuilder<InvoiceCubit, InvoiceState>(
            builder: (context, state) {
              if (state is InvoiceLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              final invoices = state is InvoiceLoaded ? state.invoices : <InvoiceModel>[];
              final hasMore = state is InvoiceLoaded ? state.hasMore : false;
              final isLoadingMore = state is InvoiceLoaded ? state.isFetchingMore : false;
              if (invoices.isEmpty) {
                return _buildEmptyState(context, controller, state);
              }
              return Column(
                children: [
                  _buildTableHeader(),
                  const Divider(height: 1),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return NotificationListener<ScrollNotification>(
                          onNotification: (ScrollNotification scrollInfo) {
                            if (state is InvoiceLoaded &&
                                !state.isFetchingMore &&
                                state.hasMore &&
                                scrollInfo.metrics.pixels >=
                                    scrollInfo.metrics.maxScrollExtent - 200) {
                              controller.fetchMore();
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: ListView.separated(
                                itemCount: invoices.length + (hasMore ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, indent: 16, endIndent: 16),
                                itemBuilder: (context, index) {
                                  if (index == invoices.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }
                                  return _buildTableRow(
                                    invoices[index],
                                    controller,
                                    index,
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
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
          SizedBox(width: 40,
              child: Text('#', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 90,
              child: Text('رقم الفاتورة', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 100,
              child: Text('التاريخ', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          Expanded(
              child: Text('العميل', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 130,
              child: Text('الإجمالي', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 130,
              child: Text('المدفوع', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 130,
              child: Text('المتبقي', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 90,
              child: Text('الحالة', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 110,
              child: Text('إجراءات', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    InvoiceModel invoice,
    InvoiceCubit controller,
    int index,
  ) {
    final isEven     = index % 2 == 0;
    final remaining  = invoice.remainingAmount;
    final remColor   = remaining > 0
        ? AppTheme.danger
        : AppTheme.success;

    return Container(
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('${index + 1}',
                style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          ),
          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                invoice.invoiceNumber
                    .toString()
                    .padLeft(6, '0'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                  fontFamily: 'Cairo',
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              AppUtils.formatDate(
                  AppUtils.parseDate(invoice.invoiceDate)),
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
            ),
          ),
          Expanded(
            child: Text(
              invoice.customerName ?? '—',
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              AppUtils.formatCurrency(invoice.netAmount),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              AppUtils.formatCurrency(invoice.paidAmount),
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.success,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              AppUtils.formatCurrency(remaining.abs()),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: remColor,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 90,
            child: Center(child: _statusBadge(invoice.status)),
          ),
          SizedBox(
            width: 130,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (invoice.status == InvoiceStatus.confirmed || invoice.status == InvoiceStatus.paid)
                  IconButton(
                    icon: const Icon(Icons.book_outlined,
                        size: 16, color: AppTheme.accent),
                    tooltip: 'عرض القيد المحاسبي',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () {
                      final BuildContext? context = rootNavigatorKey.currentContext;
                      if (context != null) {
                        _showJournalEntry(context, invoice);
                      }
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.visibility_outlined,
                      size: 16, color: AppTheme.primary),
                  tooltip: 'عرض',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () async {
                    final full = await controller
                        .getInvoiceWithItems(int.parse(invoice.id!));
                    if (full != null) {
                      _showInvoiceDetails(full);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.print_outlined,
                      size: 16, color: AppTheme.accent),
                  tooltip: 'طباعة',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () async {
                    final full = await controller
                        .getInvoiceWithItems(int.parse(invoice.id!));
                    if (full != null) {
                      await PdfService.generateAndPrint(full);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case InvoiceStatus.confirmed:
        color = AppTheme.success;
        label = 'مؤكدة';
        break;
      case InvoiceStatus.paid:
        color = AppTheme.primary;
        label = 'مدفوعة';
        break;
      case InvoiceStatus.draft:
        color = AppTheme.warning;
        label = 'مسودة';
        break;
      case InvoiceStatus.cancelled:
        color = AppTheme.danger;
        label = 'ملغاة';
        break;
      default:
        color = AppTheme.textSecondary;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showInvoiceDetails(InvoiceModel invoice) {
    showDialog(
      context: rootNavigatorKey.currentContext!,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.glassBorder)),
        child: Container(
          width: MediaQuery.of(dialogContext).size.width < 750 ? MediaQuery.of(dialogContext).size.width * 0.95 : 700,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'فاتورة رقم: ${invoice.invoiceNumber.toString().padLeft(6, '0')}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo'),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'العميل: ${invoice.customerCode ?? '—'} - ${invoice.customerName ?? '—'}  |  التاريخ: ${AppUtils.formatDate(AppUtils.parseDate(invoice.invoiceDate))}',
                style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
              ),
              const Divider(height: 24),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: AppTheme.divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      color: const Color(0x1A00E5FF),
                      child: Row(
                        children: [
                          Expanded(child: Text('الصنف',
                              style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                          SizedBox(width: 70,
                              child: Text('العدد',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                  textAlign: TextAlign.center)),
                          SizedBox(width: 80,
                              child: Text('الكمية',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                  textAlign: TextAlign.center)),
                          SizedBox(width: 90,
                              child: Text('السعر',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                  textAlign: TextAlign.center)),
                          SizedBox(width: 110,
                              child: Text('الإجمالي',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                  textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ...invoice.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.itemCode ?? ''} - ${item.itemName ?? '—'}',
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text(
                              AppUtils.formatNumber(item.piecesCount),
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '${AppUtils.formatNumber(item.quantity)} ${item.unit}',
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text(
                              AppUtils.formatCurrency(
                                  item.unitPrice),
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(
                              AppUtils.formatCurrency(
                                  item.totalPrice),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 280,
                    child: Column(
                      children: [
                        _detailRow('الإجمالي',
                            AppUtils.formatCurrency(
                                invoice.totalAmount)),
                        if (invoice.discountAmount > 0)
                          _detailRow('الخصم',
                              '- ${AppUtils.formatCurrency(invoice.discountAmount)}',
                              color: AppTheme.danger),
                        _detailRow('الصافي',
                            AppUtils.formatCurrency(
                                invoice.netAmount),
                            isBold: true),
                        _detailRow('المدفوع',
                            AppUtils.formatCurrency(
                                invoice.paidAmount),
                            color: AppTheme.success),
                        const Divider(height: 12),
                        _detailRow('المتبقي',
                            AppUtils.formatCurrency(
                                invoice.remainingAmount.abs()),
                            color: invoice.remainingAmount > 0
                                ? AppTheme.danger
                                : AppTheme.success,
                            isBold: true),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('طباعة'),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      try {
                        await PdfService.generateAndPrint(invoice);
                      } catch (e) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('خطأ: فشل إنشاء PDF: $e'),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('حفظ PDF'),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      try {
                        await PdfService.saveToFile(dialogContext, invoice);
                      } catch (e) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('خطأ: فشل حفظ الملف: $e'),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  void _showJournalEntry(BuildContext context, InvoiceModel invoice) {
    JournalEntryNavigationService.openForInvoice(
      context,
      invoiceNumber: invoice.invoiceNumber,
      invoiceId: invoice.id,
      journalEntryId: invoice.journalEntryId,
    );
  }

  Widget _detailRow(String label, String value,
      {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight:
                  isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, InvoiceCubit controller, InvoiceState state) {
    final searchQuery = state is InvoiceLoaded ? state.searchQuery : '';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 72,
              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty
                ? 'لا توجد فواتير بعد'
                : 'لا توجد نتائج',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty
                ? 'اضغط "فاتورة جديدة" لإنشاء أول فاتورة'
                : 'جرب رقم فاتورة مختلف',
            style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('فاتورة جديدة'),
              onPressed: () async {
                await controller.prepareNewInvoice();
                context.push('/invoices/new');
              },
            ),
          ],
        ],
      ),
    );
  }
}
