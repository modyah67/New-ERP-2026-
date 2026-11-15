// lib/features/journal_entry/journal_entry_preview_dialog.dart

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../core/theme.dart';
import 'journal_entry_pdf_service.dart';

/// نافذة منبثقة تفاعلية لمعاينة سند القيد المحاسبي قبل الطباعة (Print Preview).
/// تتيح فحص تفاصيل القيد، الترويسة، أطراف القيد، التوازن، والطباعة المباشرة أو التصدير كـ PDF.
class JournalEntryPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> entry;

  const JournalEntryPreviewDialog({
    super.key,
    required this.entry,
  });

  /// فتح نافذة المعاينة بشكل منبثق ديناميكي لأي قيد محاسبي
  static Future<void> show(BuildContext context, Map<String, dynamic> entry) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => JournalEntryPreviewDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entryNum = (entry['entryNum'] ??
            entry['entry_number'] ??
            entry['entryNumber'] ??
            entry['id'] ??
            '')
        .toString();
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 60 : 16,
        vertical: isDesktop ? 32 : 20,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: isDesktop ? 1150 : double.infinity,
          height: MediaQuery.of(context).size.height * 0.90,
          child: Column(
            children: [
              // ── Header Bar ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.preview_rounded,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'معاينة سند القيد المحاسبي #$entryNum قبل الطباعة',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق المعاينة',
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // ── Preview Canvas using PdfPreview ───────────────────────
              Expanded(
                child: PdfPreview(
                  maxPageWidth: 950,
                  build: (format) =>
                      JournalEntryPdfService.generateSingleVoucherPdf(entry),
                  initialPageFormat: PdfPageFormat.a4.landscape,
                  pageFormats: {
                    'A4 بالعرض': PdfPageFormat.a4.landscape,
                    'A4 بالطول': PdfPageFormat.a4,
                  },
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: 'سند_قيد_$entryNum.pdf',
                  loadingWidget: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 16),
                        Text(
                          'جاري إعداد وتنسيق سند القيد للمعاينة...',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onError: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'حدث خطأ أثناء إعداد معاينة القيد:\n$error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
