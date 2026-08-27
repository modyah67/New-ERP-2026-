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
    final isIncoming = tx.isIncoming;
    final typeColor = isIncoming ? AppTheme.success : AppTheme.danger;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45, blurRadius: 20, offset: Offset(0, 10)),
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
                      color: typeColor.withOpacity(0.15),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Details List
              _detailRow('رقم القيد المحاسبي', tx.entryNumber),
              _detailRow(
                  'التاريخ',
                  AppUtils.formatDate(
                      DateTime.tryParse(tx.createdAt) ?? DateTime.now())),
              _detailRow('نوع الحركة', tx.typeLabel),
              _detailRow('المصدر / الحساب', tx.accountSourceName),
              if (tx.relatedPartyName != null &&
                  tx.relatedPartyName!.isNotEmpty)
                _detailRow(
                  tx.relatedPartyType == 'supplier'
                      ? 'المورد'
                      : tx.relatedPartyType == 'customer'
                          ? 'العميل'
                          : 'الجهة',
                  tx.relatedPartyName!,
                ),
              if (tx.description.isNotEmpty)
                _detailRow('البيان', tx.description),
              if (tx.notes != null && tx.notes!.isNotEmpty)
                _detailRow('الملاحظة', tx.notes!),
              _detailRow(
                  'المبلغ', '${tx.currency} ${_formatAmount(tx.amount)}'),
              _detailRow('العملة', tx.currency),
              if (tx.categoryName != null && tx.categoryName!.isNotEmpty)
                _detailRow('التصنيف', tx.categoryName!),
              if (tx.referenceNumber != null && tx.referenceNumber!.isNotEmpty)
                _detailRow('رقم المرجع / الشيك', tx.referenceNumber!),
              if (tx.creatorName != null && tx.creatorName!.isNotEmpty)
                _detailRow('المستخدم المنفذ', tx.creatorName!),
              _detailRow('حالة الحركة', isIncoming ? 'وارد' : 'صادر',
                  valueColor: isIncoming ? AppTheme.success : AppTheme.danger),
              _detailRow('الرصيد قبل',
                  '${tx.currency} ${_formatAmount(tx.balanceBefore)}'),
              _detailRow('الرصيد بعد',
                  '${tx.currency} ${_formatAmount(tx.balanceAfter)}'),
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
                          foregroundColor: AppTheme.accent,
                          side: const BorderSide(color: AppTheme.accent),
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

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 13, fontFamily: 'Cairo')),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: valueColor ?? Colors.white,
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
