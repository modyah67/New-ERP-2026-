// lib/features/returns/return_form_page.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/invoice_model.dart';
import '../invoices/invoice_cubit.dart';
import '../invoices/invoice_state.dart';
import 'return_preview_page.dart';
import '../../ui/widgets/app_text_field.dart';
import '../../ui/widgets/app_search_field.dart';

class ReturnFormPage extends StatelessWidget {
  const ReturnFormPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<InvoiceCubit>();
    return Scaffold(
      appBar: _buildAppBar(context, controller),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 320,
              child: _buildLeftPanel(controller, context)),
          const VerticalDivider(width: 1),
          Expanded(child: _buildRightPanel(controller)),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, InvoiceCubit c) {
    return AppBar(
      title: Text(
        'مرتجع جديد — رقم ${c.nextInvoiceNumber.toString().padLeft(6, '0')}',
        style: const TextStyle(fontFamily: 'Cairo',
            fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
      ),
      leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context)),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.warning),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('معاينة وحفظ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              final ctrl = context.read<InvoiceCubit>();
              if (ctrl.selectedCustomer == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى اختيار العميل أولاً'),
                    backgroundColor: AppTheme.warning,
                  ),
                );
                return;
              }
              final hasLines = ctrl.invoiceLines
                  .any((l) => l.selectedItem != null && l.quantity > 0);
              if (!hasLines) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إضافة صنف واحد على الأقل'),
                    backgroundColor: AppTheme.warning,
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: ctrl,
                    child: const ReturnPreviewPage(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLeftPanel(InvoiceCubit c, BuildContext ctx) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('بيانات المرتجع'),
            const SizedBox(height: 12),

            // Return number (read-only)
            Text('رقم المرتجع', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.tag, size: 16, color: AppTheme.warning),
                const SizedBox(width: 8),
                Text(
                  c.nextInvoiceNumber.toString().padLeft(6, '0'),
                  style: const TextStyle(fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.warning, fontFamily: 'Cairo'),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('تلقائي',
                      style: TextStyle(fontSize: 10,
                          color: AppTheme.success, fontFamily: 'Cairo')),
                ),
              ]),
            ),

            const SizedBox(height: 16),

            // Date
            Text('تاريخ المرتجع', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => c.pickDate(ctx),
              borderRadius: BorderRadius.circular(8),
              child: BlocBuilder<InvoiceCubit, InvoiceState>(
                builder: (context, state) {
                  final date = c.invoiceDate;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFBDBDBD)),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white.withValues(alpha: 0.03),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(AppUtils.formatDate(date),
                          style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                    ]),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Customer (AppSearchField)
            AppSearchField<CustomerModel>(
              label: 'العميل',
              controller: c.customerSearchController,
              focusNode: c.customerFocusNode,
              isRequired: true,
              hint: 'ابحث بالاسم أو الكود...',
              prefixIcon: const Icon(Icons.person_outline, size: 18),
              highlightColor: AppTheme.primary.withValues(alpha: 0.5),
              suggestionsCallback: (pattern) {
                if (pattern.isEmpty) return c.customers;
                return c.customers.where((cu) =>
                    cu.name.toLowerCase().contains(pattern.toLowerCase())).toList();
              },
              itemBuilder: (context, cu) {
                return ListTile(
                  title: Text(cu.name, style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                  subtitle: Text(cu.name, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                );
              },
              onSelected: (cu) {
                c.setSelectedCustomer(cu);
                c.customerSearchController.text = cu.name;
                if (c.invoiceLines.isNotEmpty) {
                  c.invoiceLines.first.itemFocus.requestFocus();
                }
              },
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // ── Discount section ──────────────
            _sectionTitle('الخصم'),
            const SizedBox(height: 10),

            // Discount mode radio buttons
            BlocBuilder<InvoiceCubit, InvoiceState>(
              builder: (context, state) {
                return Column(
                  children: [
                    _discountRadio(c, DiscountMode.none, 'بدون خصم',
                        Colors.grey),
                    const SizedBox(height: 6),
                    _discountRadio(c, DiscountMode.fixed, 'خصم ثابت (ج.م)',
                        AppTheme.danger),
                    const SizedBox(height: 6),
                    _discountRadio(c, DiscountMode.percentage, 'خصم نسبة (%)',
                        AppTheme.warning),
                  ],
                );
              },
            ),

            const SizedBox(height: 10),

            // Discount input
            BlocBuilder<InvoiceCubit, InvoiceState>(
              builder: (context, state) {
                if (c.discountMode == DiscountMode.none) {
                  return const SizedBox.shrink();
                }
                return AppTextField(
                  label: c.discountMode == DiscountMode.percentage
                      ? 'النسبة (%)' : 'المبلغ (ج.م)',
                  controller: c.discountController,
                  focusNode: c.discountFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  hint: '0.00',
                  onChanged: (_) => c.refreshTotals(),
                );
              },
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const SizedBox(height: 12),

            // Notes
            AppTextField(
              label: 'ملاحظات',
              controller: c.notesController,
              focusNode: c.notesFocusNode,
              hint: 'ملاحظات اختيارية...',
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Live totals
            _buildTotalsSummary(c),
          ],
        ),
      ),
    );
  }

  Widget _discountRadio(
      InvoiceCubit c, DiscountMode mode, String label, Color color) {
    final isSelected = c.discountMode == mode;
    return GestureDetector(
      onTap: () => c.setDiscountMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: isSelected ? color : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13,
                  color: isSelected ? color : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSummary(InvoiceCubit c) {
    return BlocBuilder<InvoiceCubit, InvoiceState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('الإجماليات'),
            const SizedBox(height: 12),
            _totRow('إجمالي الأصناف',
                AppUtils.formatCurrency(c.subtotal)),
            if (c.discountAmount > 0) ...[
              const SizedBox(height: 6),
              _totRow('الخصم',
                  '- ${AppUtils.formatCurrency(c.discountAmount)}',
                  color: AppTheme.danger),
            ],
            const Divider(height: 16),
            _totRow('الصافي', AppUtils.formatCurrency(c.netTotal),
                bold: true, size: 15),
            const SizedBox(height: 6),
            _totRow('المدفوع', AppUtils.formatCurrency(c.paidAmount),
                color: AppTheme.success),
            const Divider(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.remainingAmount > 0
                    ? AppTheme.danger.withValues(alpha: 0.08)
                    : AppTheme.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _totRow('المتبقي',
                  AppUtils.formatCurrency(c.remainingAmount.abs()),
                  color: c.remainingAmount > 0
                      ? AppTheme.danger : AppTheme.success,
                  bold: true, size: 16),
            ),
            if (c.totalMeters > 0) ...[
              const SizedBox(height: 12),
              _totRow('إجمالي الأمتار',
                  '${AppUtils.formatNumber(c.totalMeters)} م',
                  color: AppTheme.primary),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRightPanel(InvoiceCubit c) {
    return Container(
      color: AppTheme.background,
      child: Column(children: [
        _buildItemsHeader(c),
        const Divider(height: 1),
        Expanded(
          child: BlocBuilder<InvoiceCubit, InvoiceState>(
            builder: (context, state) {
              return c.invoiceLines.isEmpty
                  ? _emptyLines()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: c.invoiceLines.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _buildItemRow(c, i),
                    );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildItemsHeader(InvoiceCubit c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppTheme.surface,
      child: Row(children: [
        Text('بنود المرتجع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
        const Spacer(),
        BlocBuilder<InvoiceCubit, InvoiceState>(
          builder: (context, state) {
            return Text('${c.invoiceLines.length} بند',
                style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13));
          },
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('إضافة بند'),
          onPressed: c.addNewLine,
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10)),
        ),
      ]),
    );
  }

  Widget _buildItemRow(InvoiceCubit c, int idx) {
    final line = c.invoiceLines[idx];
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: EdgeInsets.zero,
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
              // Row badge
              Container(
                width: 28, height: 28,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text('${idx + 1}',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warning, fontFamily: 'Cairo'))),
              ),
              const SizedBox(width: 12),

              // Item dropdown (AppSearchField)
              Expanded(
                flex: 3,
                child: _ItemDropdown(controller: c, lineIndex: idx, line: line),
              ),
              const SizedBox(width: 10),

              // Pieces count (العدد)
              SizedBox(width: 80,
                child: AppTextField(
                  label: 'العدد',
                  controller: line.piecesController,
                  focusNode: line.piecesFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  hint: '0',
                ),
              ),
              const SizedBox(width: 10),

              // Quantity
              SizedBox(width: 110,
                child: BlocBuilder<InvoiceCubit, InvoiceState>(
                  builder: (context, state) {
                    String? errorMsg;
                    if (!c.isReturn && line.selectedItem != null) {
                      final totalQty = c.invoiceLines
                          .where((l) => l.selectedItem?.id == line.selectedItem!.id)
                          .fold(0.0, (sum, l) => sum + l.quantity);
                      if (totalQty > line.selectedItem!.stockQuantity) {
                        errorMsg = 'متاح ${line.selectedItem!.stockQuantity} فقط';
                      }
                    }
                    return AppTextField(
                      label: 'الكمية',
                      controller: line.quantityController,
                      focusNode: line.quantityFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) => c.onQuantityChanged(idx, v),
                      hint: '0.00',
                      errorText: errorMsg,
                      suffixIcon: Center(widthFactor: 1, child: Text(line.unit, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13))),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Price
              SizedBox(width: 120,
                child: AppTextField(
                  label: 'السعر',
                  controller: line.priceController,
                  focusNode: line.priceFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => c.onPriceChanged(idx, v),
                  hint: '0.00',
                  suffixIcon: Center(widthFactor: 1, child: Text('ج.م', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13))),
                ),
              ),
              const SizedBox(width: 10),

              // Total (reactive)
              SizedBox(
                width: 130,
                child: BlocBuilder<InvoiceCubit, InvoiceState>(
                  builder: (context, state) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الإجمالي', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
                        const SizedBox(height: 6),
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.success.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            AppUtils.formatCurrency(line.totalPrice),
                            style: const TextStyle(fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success, fontFamily: 'Cairo'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Delete
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppTheme.danger, size: 20),
                  tooltip: 'حذف البند',
                  onPressed: () => c.removeLine(idx),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _emptyLines() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_add, size: 64,
              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('لا توجد بنود بعد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text('اضغط "إضافة بند"', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'));

  Widget _totRow(String label, String value,
      {Color? color, bool bold = false, double size = 13}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontFamily: 'Cairo',
            fontSize: size, color: AppTheme.textSecondary)),
        Text(value, style: TextStyle(fontFamily: 'Cairo',
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.white)),
      ],
    );
  }
}

// ── Item dropdown (AppSearchField) ─────────────────────────────
class _ItemDropdown extends StatelessWidget {
  final InvoiceCubit controller;
  final int lineIndex;
  final InvoiceLine line;

  const _ItemDropdown({
    required this.controller,
    required this.lineIndex,
    required this.line,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InvoiceCubit, InvoiceState>(
      builder: (context, state) {
        return AppSearchField<ItemModel>(
          label: 'الصنف',
          controller: line.itemSearchController,
          focusNode: line.itemFocus,
          hint: 'اختر الصنف...',
          highlightColor: AppTheme.primary.withValues(alpha: 0.5),
          suggestionsCallback: (pattern) {
            if (pattern.isEmpty) return <ItemModel>[];
            return controller.allItems.where((it) =>
                it.name.toLowerCase().contains(pattern.toLowerCase()) ||
                it.code.toLowerCase().contains(pattern.toLowerCase())).toList();
          },
          itemBuilder: (context, it) {
            return ListTile(
              title: Text(it.name, style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
              subtitle: Text(it.code, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
              trailing: Text(it.stockQuantity.toString(), style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
            );
          },
          onSelected: (it) {
            controller.onItemSelected(lineIndex, it);
            line.quantityFocus.requestFocus();
          },
        );
      },
    );
  }
}
