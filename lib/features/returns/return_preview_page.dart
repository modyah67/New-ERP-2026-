// lib/features/returns/return_preview_page.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/invoice_model.dart';
import '../../ui/pages/shell_page.dart';
import '../invoices/invoice_cubit.dart';
import '../invoices/invoice_state.dart';
import '../invoices/pdf_service.dart';

class ReturnPreviewPage extends StatefulWidget {
  const ReturnPreviewPage({super.key});

  @override
  State<ReturnPreviewPage> createState() =>
      _ReturnPreviewPageState();
}

class _ReturnPreviewPageState
    extends State<ReturnPreviewPage> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final c = context.read<InvoiceCubit>();
    return Scaffold(
      appBar: _buildAppBar(context, c),
      body: Row(
        children: [
          SizedBox(width: 290,
              child: _buildActionPanel(context, c)),
          const VerticalDivider(width: 1),
          Expanded(child: _buildA4Preview(c)),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, InvoiceCubit c) {
    return AppBar(
      title: Text(
        'معاينة — مرتجع رقم '
        '${c.nextInvoiceNumber.toString().padLeft(6, '0')}',
        style: const TextStyle(fontFamily: 'Cairo',
            fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'رجوع للتعديل',
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  // ── Left action panel ─────────────────────

  Widget _buildActionPanel(BuildContext context, InvoiceCubit c) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                const Icon(Icons.preview_outlined,
                    color: AppTheme.warning, size: 28),
                const SizedBox(height: 8),
                const Text('معاينة قبل الحفظ',
                    style: TextStyle(fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14, color: AppTheme.warning),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text('راجع المرتجع ثم اختر إجراءً',
                    style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)
                        .copyWith(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center),
              ]),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // Summary
            _buildSummary(c),
            const SizedBox(height: 24),

            // Buttons
            _buildButtons(context, c),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(InvoiceCubit c) {
    return BlocBuilder<InvoiceCubit, InvoiceState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ملخص', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
            const SizedBox(height: 12),
            _sRow('العميل',
                c.selectedCustomer?.name ?? '—'),
            const SizedBox(height: 5),
            _sRow('الأصناف',
                '${c.invoiceLines.where((l) => l.selectedItem != null).length} صنف'),
            if (c.totalMeters > 0) ...[
              const SizedBox(height: 5),
              _sRow('الأمتار',
                  '${AppUtils.formatNumber(c.totalMeters)} م'),
            ],
            const Divider(height: 16),
            _sRow('الإجمالي',
                AppUtils.formatCurrency(c.subtotal)),
            if (c.discountAmount > 0) ...[
              const SizedBox(height: 5),
              _sRow('الخصم',
                  '- ${AppUtils.formatCurrency(c.discountAmount)}',
                  color: AppTheme.danger),
            ],
            const SizedBox(height: 5),
            _sRow('الصافي',
                AppUtils.formatCurrency(c.netTotal),
                bold: true, size: 15),
            const SizedBox(height: 5),
            _sRow('المدفوع',
                AppUtils.formatCurrency(c.paidAmount),
                color: AppTheme.success),
            const Divider(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.remainingAmount > 0
                    ? AppTheme.danger.withValues(alpha: 0.06)
                    : AppTheme.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _sRow('المتبقي',
                  AppUtils.formatCurrency(c.remainingAmount.abs()),
                  bold: true, size: 15,
                  color: c.remainingAmount > 0
                      ? AppTheme.danger : AppTheme.success),
            ),
          ],
        );
      },
    );
  }

  Widget _sRow(String label, String value,
      {bool bold = false, double size = 13, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)
            .copyWith(color: AppTheme.textSecondary)),
        Text(value, style: TextStyle(fontFamily: 'Cairo',
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.white)),
      ],
    );
  }

  Widget _buildButtons(BuildContext context, InvoiceCubit c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1) Confirm save
        ElevatedButton.icon(
          icon: _isSaving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline, size: 20),
          label: Text(_isSaving ? 'جارٍ الحفظ...' : 'تأكيد الحفظ',
              style: const TextStyle(fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _isSaving ? null : () => _confirmSave(c),
        ),

        const SizedBox(height: 10),

        // 2) Back to edit
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('رجوع للتعديل',
              style: TextStyle(fontFamily: 'Cairo')),
          onPressed: () => Navigator.pop(context),
        ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 10),

        // 3) PDF only
        OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined,
              size: 18, color: AppTheme.danger),
          label: const Text('طباعة PDF',
              style: TextStyle(color: AppTheme.danger,
                  fontFamily: 'Cairo')),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.danger)),
          onPressed: () => _previewPdf(context, c),
        ),

        const SizedBox(height: 10),

        // 4) Save PDF
        ElevatedButton.icon(
          icon: const Icon(Icons.save_alt, size: 18),
          label: const Text('حفظ PDF',
              style: TextStyle(fontFamily: 'Cairo')),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary),
          onPressed: () => _savePdf(context, c),
        ),
      ],
    );
  }

  // ── A4 preview panel ──────────────────────

  Widget _buildA4Preview(InvoiceCubit c) {
    return Container(
      color: const Color(0xFFE8E8E8),
      child: LayoutBuilder(builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            height: availableHeight.isFinite
                ? null
                : MediaQuery.of(context).size.height * 0.85,
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width < 640 ? MediaQuery.of(context).size.width * 0.95 : 595,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _a4Body(c),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _a4Body(InvoiceCubit c) {
    final lines = c.invoiceLines
        .where((l) => l.selectedItem != null && l.quantity > 0)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Text(
            'فاتورة مرتجع',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _a4InfoBox(c),
        const SizedBox(height: 16),
        _a4Table(lines),
        const SizedBox(height: 12),
        _a4Totals(c),
        const SizedBox(height: 12),
        _a4Words(c),
        if (c.notesController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _a4Notes(c.notesController.text.trim()),
        ],
        const SizedBox(height: 20),
        _a4Signatures(),
      ],
    );
  }



  Widget _a4InfoBox(InvoiceCubit c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Expanded(child: _infoCell('العميل',
              c.selectedCustomer?.name ?? '—')),
          Container(width: 1, height: 36,
              color: const Color(0xFFBDBDBD)),
          Expanded(child: Center(child: _infoCell('التاريخ',
              AppUtils.formatDate(c.invoiceDate)))),
          Container(width: 1, height: 36,
              color: const Color(0xFFBDBDBD)),
          Expanded(child: Align(
            alignment: Alignment.centerLeft,
            child: _infoCell('رقم المرتجع',
                c.nextInvoiceNumber.toString().padLeft(6, '0'),
                bold: true, color: Colors.black),
          )),
        ],
      ),
    );
  }

  Widget _infoCell(String label, String value,
      {bool bold = false, Color? color}) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 10,
          color: AppTheme.textSecondary, fontFamily: 'Cairo')),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color ?? AppTheme.textPrimary, fontFamily: 'Cairo')),
    ]);
  }

  Widget _a4Table(List<InvoiceLine> lines) {
    return Table(
      border: TableBorder.all(
          color: const Color(0xFFE0E0E0), width: 0.5),
      columnWidths: const {
        0: FixedColumnWidth(28),
        1: FlexColumnWidth(3),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(0.8),
        4: FlexColumnWidth(1.2),
        5: FlexColumnWidth(1.5),
        6: FlexColumnWidth(1.5),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Colors.black87),
          children: ['#', 'الصنف', 'الكود', 'الكمية', 'العدد',
                     'السعر', 'الإجمالي']
              .map((h) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    child: Text(h, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo', fontSize: 11)),
                  )).toList(),
        ),
        ...lines.asMap().entries.map((e) {
          final l = e.value;
          final pc = double.tryParse(l.piecesController.text) ?? 0.0;
          final pcStr = pc % 1 == 0 ? pc.toInt().toString() : pc.toString();
          return TableRow(
            decoration: BoxDecoration(
                color: e.key % 2 == 0
                    ? Colors.white : const Color(0xFFF9F9F9)),
            children: [
              _tc('${e.key + 1}'),
              _tc(l.selectedItem?.name ?? '—', right: true),
              _tc(l.selectedItem?.code ?? '—'),
              _tc('${AppUtils.formatNumber(l.quantity)} ${l.unit}'),
              _tc(pcStr),
              _tc(AppUtils.formatCurrency(l.unitPrice)),
              _tc(AppUtils.formatCurrency(l.totalPrice), bold: true),
            ],
          );
        }),
      ],
    );
  }

  Widget _tc(String t, {bool right = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(t,
          textAlign: right ? TextAlign.right : TextAlign.center,
          style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _a4Totals(InvoiceCubit c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 230,
          decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(6)),
          child: Column(children: [
            _tRow('الإجمالي', AppUtils.formatCurrency(c.subtotal)),
            if (c.discountAmount > 0)
              _tRow('الخصم',
                  '- ${AppUtils.formatCurrency(c.discountAmount)}',
                  vc: Colors.black),
            _tRow('الصافي', AppUtils.formatCurrency(c.netTotal),
                bold: true),
            _tRow('المدفوع', AppUtils.formatCurrency(c.paidAmount),
                vc: Colors.black),
            Container(
              color: const Color(0xFFF5F5F5),
              child: _tRow('المتبقي',
                  AppUtils.formatCurrency(c.remainingAmount.abs()),
                  bold: true,
                  vc: Colors.black),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _tRow(String label, String value,
      {bool bold = false, Color? vc}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value,
              style: TextStyle(fontFamily: 'Cairo',
                  fontSize: bold ? 13 : 11,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: vc ?? Colors.white)),
          Text(label, style: const TextStyle(fontFamily: 'Cairo',
              fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _a4Words(InvoiceCubit c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFFE0E0E0), width: 0.5),
      ),
      child: Row(children: [
        Expanded(
          child: Text(AppUtils.numberToArabicWords(c.netTotal),
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontFamily: 'Cairo',
                  fontSize: 11, color: Colors.black)),
        ),
        const SizedBox(width: 8),
        const Text('فقط لا غير:',
            style: TextStyle(fontFamily: 'Cairo',
                fontSize: 11, fontWeight: FontWeight.bold,
                color: Colors.black)),
      ]),
    );
  }

  Widget _a4Notes(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBDBDBD), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('ملاحظات:',
              style: TextStyle(fontFamily: 'Cairo',
                  fontSize: 10, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(notes,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontFamily: 'Cairo',
                  fontSize: 11, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _a4Signatures() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _sig('توقيع العميل'),
        _sig('توقيع المسؤول'),
        _sig('الختم'),
      ],
    );
  }

  Widget _sig(String label) {
    return Column(children: [
      Container(width: 120, height: 44,
          decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: Color(0xFFBDBDBD), width: 0.5)))),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontFamily: 'Cairo',
          fontSize: 10, color: AppTheme.textSecondary)),
    ]);
  }

  // ── Actions ───────────────────────────────

  Future<void> _confirmSave(InvoiceCubit c) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final ok = await c.saveInvoice();
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ المرتجع بنجاح')),
      );
      context.go('/returns');
    } else if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('حدث خطأ أثناء حفظ المرتجع'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _previewPdf(BuildContext context, InvoiceCubit c) async {
    final inv = c.buildPreviewInvoice();
    if (inv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أضف بنوداً صالحة أولاً'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    try {
      await PdfService.generateAndPrint(inv);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إنشاء PDF: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _savePdf(BuildContext context, InvoiceCubit c) async {
    final inv = c.buildPreviewInvoice();
    if (inv == null) return;
    try {
      final file = await PdfService.saveToFile(context, inv);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الملف بنجاح في:\n${file.path}'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }
}
