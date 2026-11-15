import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../data/models/unified_transaction_model.dart';
import '../../../data/services/journal_entry_navigation_service.dart';
import '../treasury_pdf_service.dart';

class UnifiedTransactionDetailsModal extends StatelessWidget {
  final UnifiedTransactionModel tx;

  const UnifiedTransactionDetailsModal({super.key, required this.tx});

  static void show(BuildContext context, UnifiedTransactionModel tx) {
    showDialog(
      context: context,
      builder: (_) => UnifiedTransactionDetailsModal(tx: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIncoming = tx.isIncoming;
    final typeColor = isIncoming ? AppTheme.success : AppTheme.danger;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
          boxShadow: [
            BoxShadow(
                color: isDark ? Colors.black45 : Colors.black12,
                blurRadius: 20,
                offset: const Offset(0, 10)),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title & Close Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isIncoming
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: typeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    tx.typeLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'عرض القيد المحاسبي',
                    icon: const Icon(Icons.book_outlined,
                        color: AppTheme.accent, size: 22),
                    onPressed: () {
                      Navigator.pop(context);
                      JournalEntryNavigationService.openForTransaction(
                        context,
                        journalEntryId: tx.journalEntryId,
                        entryNumber: tx.entryNumber,
                        txId: tx.id,
                        description: tx.description,
                        sourceType: tx.transactionType,
                        sourceId: tx.id,
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'طباعة سند الحركة',
                    icon: const Icon(Icons.print_outlined,
                        color: AppTheme.accent, size: 22),
                    onPressed: () => TreasuryPdfService.printVoucher(tx),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: isDark ? Colors.white70 : Colors.black, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Details List
              _detailRow('رقم القيد المحاسبي', tx.entryNumber, isDark: isDark),
              _detailRow(
                  'التاريخ',
                  AppUtils.formatDate(
                      DateTime.tryParse(tx.createdAt) ?? DateTime.now()),
                  isDark: isDark),
              _detailRow('نوع الحركة', tx.typeLabel, isDark: isDark),
              _detailRow('المصدر / الحساب', tx.accountSourceName, isDark: isDark),
              if (tx.relatedPartyName != null &&
                  tx.relatedPartyName!.isNotEmpty)
                _detailRow(
                  tx.relatedPartyType == 'supplier'
                      ? 'المورد'
                      : tx.relatedPartyType == 'customer'
                          ? 'العميل'
                          : 'الجهة',
                  tx.relatedPartyName!,
                  isDark: isDark,
                ),
              if (tx.description.isNotEmpty)
                _detailRow('البيان', tx.description, isDark: isDark),
              if (tx.notes != null && tx.notes!.isNotEmpty)
                _detailRow('الملاحظة', tx.notes!, isDark: isDark),
              _detailRow(
                  'المبلغ', '${tx.currency} ${_formatAmount(tx.amount)}',
                  isDark: isDark),
              _detailRow('العملة', tx.currency, isDark: isDark),
              if (tx.categoryName != null && tx.categoryName!.isNotEmpty)
                _detailRow('التصنيف', tx.categoryName!, isDark: isDark),
              if (tx.referenceNumber != null && tx.referenceNumber!.isNotEmpty)
                _detailRow('رقم المرجع / الشيك', tx.referenceNumber!, isDark: isDark),
              if (tx.creatorName != null && tx.creatorName!.isNotEmpty)
                _detailRow('المستخدم المنفذ', tx.creatorName!, isDark: isDark),
              _detailRow('حالة الحركة', isIncoming ? 'وارد' : 'صادر',
                  valueColor: isIncoming ? AppTheme.success : AppTheme.danger,
                  isDark: isDark),
              _detailRow('الرصيد قبل',
                  '${tx.currency} ${_formatAmount(tx.balanceBefore)}',
                  isDark: isDark),
              _detailRow('الرصيد بعد',
                  '${tx.currency} ${_formatAmount(tx.balanceAfter)}',
                  isDark: isDark),
              const SizedBox(height: 24),

              // Buttons Row
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          JournalEntryNavigationService.openForTransaction(
                            context,
                            journalEntryId: tx.journalEntryId,
                            entryNumber: tx.entryNumber,
                            txId: tx.id,
                            description: tx.description,
                            sourceType: tx.transactionType,
                            sourceId: tx.id,
                          );
                        },
                        icon: const Icon(Icons.book_outlined, size: 18),
                        label: const Text(
                          'عرض القيد المحاسبي',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                          side: BorderSide(color: isDark ? AppTheme.accent : const Color(0xFF0F766E)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: () => TreasuryPdfService.printVoucher(tx),
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text(
                          'طباعة / معاينة سند الحركة',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {Color? valueColor, required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: valueColor ?? (isDark ? Colors.white : Colors.black),
                fontWeight: FontWeight.bold,
                fontSize: 13,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amt) {
    return AppUtils.formatNumber(amt);
  }
}
