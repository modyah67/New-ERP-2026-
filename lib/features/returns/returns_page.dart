// lib/features/returns/returns_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/router.dart' show rootNavigatorKey, RoutePaths;
import '../../data/models/invoice_model.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import '../invoices/invoice_cubit.dart';
import '../invoices/invoice_state.dart';
import '../invoices/pdf_service.dart';

class ReturnsPage extends StatelessWidget {
  const ReturnsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.read<InvoiceCubit>();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.keyboard_return,
                    color: AppTheme.warning, size: 22),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('المرتجعات', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                BlocBuilder<InvoiceCubit, InvoiceState>(
                  builder: (context, state) {
                    final count = state is InvoiceLoaded ? state.invoices.length : 0;
                    return Text('$count مرتجع',
                        style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13));
                  },
                ),
              ]),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh_outlined),
                  tooltip: 'تحديث', onPressed: c.loadAll),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('مرتجع جديد'),
                onPressed: () { c.prepareNewForm(); context.push('/returns/new'); },
              ),
            ]),
            const SizedBox(height: 20),
            // Search
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ClipRRect(borderRadius: BorderRadius.circular(24), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: Container(decoration: AppTheme.glassCard(), child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'بحث بالرقم أو اسم العميل...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                      onChanged: (v) => c.onSearchChanged(v),
                    ),
                  ))))),
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
                            onTap: () => c.pickFromDate(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(children: [
                                const Icon(Icons.calendar_today, size: 16, color: AppTheme.warning),
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
                            onTap: () => c.pickToDate(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(children: [
                                const Icon(Icons.calendar_today, size: 16, color: AppTheme.warning),
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
                              onPressed: c.clearDateFilter,
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
            ),
            const SizedBox(height: 16),
            // Table
            Expanded(child: BlocBuilder<InvoiceCubit, InvoiceState>(
              builder: (context, state) {
                if (state is InvoiceLoading) return const Center(child: CircularProgressIndicator());
                final invoices = state is InvoiceLoaded ? state.invoices : <InvoiceModel>[];
                final hasMore = state is InvoiceLoaded ? state.hasMore : false;
                if (invoices.isEmpty) return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.keyboard_return, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('لا توجد مرتجعات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                  ],
                ));
                return ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: AppTheme.glassCard(),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          color: const Color(0x1A00E5FF),
                          child: Row(children: [
                            SizedBox(width: 80, child: Text('الرقم', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                            SizedBox(width: 100, child: Text('التاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                            Expanded(child: Text('العميل', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                            SizedBox(width: 120, child: Text('الإجمالي', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                            SizedBox(width: 120, child: Text('المدفوع', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                            SizedBox(width: 100, child: Text('الحالة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                            SizedBox(width: 60, child: Text('عرض', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                          ]),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (ScrollNotification scrollInfo) {
                              if (state is InvoiceLoaded &&
                                  !state.isFetchingMore &&
                                  state.hasMore &&
                                  scrollInfo.metrics.pixels >=
                                      scrollInfo.metrics.maxScrollExtent - 200) {
                                c.fetchMore();
                              }
                              return false;
                            },
                            child: ListView.separated(
                              itemCount: invoices.length + (hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                              itemBuilder: (context, i) {
                                if (i == invoices.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                return _row(context, c, i);
                              },
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            )),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, InvoiceCubit c, int i) {
    final inv = c.invoices[i];
    final even = i % 2 == 0;
    final rem = inv.remainingAmount;
    return Container(
      color: even ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        SizedBox(width: 80, child: Text(inv.invoiceNumber.toString().padLeft(6, '0'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Colors.white))),
        SizedBox(width: 100, child: Text(AppUtils.formatDate(AppUtils.parseDate(inv.invoiceDate)), style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15))),
        Expanded(child: Text(inv.customerName ?? '—', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15), overflow: TextOverflow.ellipsis)),
        SizedBox(width: 120, child: Text(AppUtils.formatCurrency(inv.netAmount),
            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13, color: Colors.white), textAlign: TextAlign.center)),
        SizedBox(width: 120, child: Text(AppUtils.formatCurrency(inv.paidAmount), style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15), textAlign: TextAlign.center)),
        SizedBox(width: 100, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: (rem <= 0 ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(rem <= 0 ? 'مسدد' : 'غير مسدد', style: TextStyle(color: rem <= 0 ? AppTheme.success : AppTheme.danger, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center),
        )),
        SizedBox(width: 90, child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (inv.status == 'confirmed' || inv.status == 'paid')
              IconButton(
                icon: const Icon(Icons.book_outlined, size: 16, color: AppTheme.accent),
                tooltip: 'عرض القيد المحاسبي',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _showJournalEntry(context, inv),
              ),
            IconButton(icon: const Icon(Icons.visibility_outlined, size: 18, color: Colors.white), tooltip: 'عرض',
                onPressed: () async {
                  final full = await c.getInvoiceWithItems(int.parse(inv.id!));
                  if (full != null) _showDetails(full);
                }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
          ],
        )),
      ]),
    );
  }

  void _showDetails(InvoiceModel invoice) {
    showDialog(
      context: rootNavigatorKey.currentContext!,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                  // Header
                  Row(
                    children: [
                      Text(
                        'مرتجع مبيعات رقم: ${invoice.invoiceNumber.toString().padLeft(6, '0')}',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo'),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'العميل: ${invoice.customerCode ?? '—'} - ${invoice.customerName ?? '—'}  |  التاريخ: ${AppUtils.formatDate(AppUtils.parseDate(invoice.invoiceDate))}',
                    style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                  ),
                  const Divider(height: 24),

                  // Items table
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppTheme.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          color: const Color(0x1A00E5FF),
                          child: Row(
                            children: [
                              Expanded(child: Text('الصنف',
                                  style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                              SizedBox(width: 70,
                                  child: Text('العدد',
                                      style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                      textAlign: TextAlign.center)),
                              SizedBox(width: 80,
                                  child: Text('الكمية',
                                      style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                      textAlign: TextAlign.center)),
                              SizedBox(width: 90,
                                  child: Text('السعر',
                                      style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                      textAlign: TextAlign.center)),
                              SizedBox(width: 110,
                                  child: Text('الإجمالي',
                                      style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                                      textAlign: TextAlign.center)),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Rows
                        ...invoice.items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.itemCode ?? ''} - ${item.itemName ?? '—'}',
                                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  AppUtils.formatNumber(item.piecesCount),
                                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '${AppUtils.formatNumber(item.quantity)} ${item.unit}',
                                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  AppUtils.formatCurrency(
                                      item.unitPrice),
                                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
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

                  // Totals
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
                      // Print button
                      OutlinedButton.icon(
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: const Text('طباعة'),
                        onPressed: () async {
                          Navigator.pop(dialogContext); // close dialog first
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
                      // Save PDF button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('حفظ PDF'),
                        onPressed: () async {
                          Navigator.pop(dialogContext); // close dialog first
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
          Text(label, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
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
}
