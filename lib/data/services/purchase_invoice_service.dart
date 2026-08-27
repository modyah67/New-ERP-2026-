import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PurchaseInvoiceService {
  static final _client = Supabase.instance.client;

  /// Recalculates paid_amount, remaining_amount, and payment_status for a purchase invoice
  /// by summing up all payments in treasury_transactions, cashbox_transactions, and bank_account_transactions.
  static Future<void> recalculate(String invoiceId) async {
    try {
      // 1. Fetch the purchase invoice to get the total_amount, discount_amount, invoice_number, and paid_amount
      final idVal = int.tryParse(invoiceId) ?? invoiceId;
      final invoiceData = await _client
          .from('purchase_invoices')
          .select('id, invoice_number, total_amount, discount_amount, paid_amount')
          .eq('id', idVal)
          .maybeSingle();

      if (invoiceData == null) return;

      final invoiceNumber = invoiceData['invoice_number']?.toString();
      final refIds = <String>{
        invoiceId.toString(),
        if (invoiceNumber != null && invoiceNumber.isNotEmpty) invoiceNumber,
      }.toList();

      final totalAmount = (invoiceData['total_amount'] as num?)?.toDouble() ?? 0.0;
      final discountAmount = (invoiceData['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final netAmount = (totalAmount - discountAmount).clamp(0.0, double.infinity);

      double totalPaidFromTxs = 0.0;

      // 2. Fetch total from treasury_transactions
      try {
        final treasuryTxs = await _client
            .from('treasury_transactions')
            .select('amount, type')
            .eq('reference_type', 'purchase_invoice')
            .inFilter('reference_id', refIds);

        for (final tx in (treasuryTxs as List)) {
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          totalPaidFromTxs += amt;
        }
      } catch (e) {
        debugPrint('PurchaseInvoiceService: error querying treasury_transactions: $e');
      }

      // 3. Fetch total from cashbox_transactions
      try {
        final cashboxTxs = await _client
            .from('cashbox_transactions')
            .select('amount')
            .eq('reference_type', 'purchase_invoice')
            .inFilter('reference_id', refIds);

        for (final tx in (cashboxTxs as List)) {
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          totalPaidFromTxs += amt;
        }
      } catch (e) {
        debugPrint('PurchaseInvoiceService: error querying cashbox_transactions: $e');
      }

      // 4. Fetch total from bank_account_transactions
      try {
        final bankTxs = await _client
            .from('bank_account_transactions')
            .select('amount')
            .eq('reference_type', 'purchase_invoice')
            .inFilter('reference_id', refIds);

        for (final tx in (bankTxs as List)) {
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          totalPaidFromTxs += amt;
        }
      } catch (e) {
        debugPrint('PurchaseInvoiceService: error querying bank_account_transactions: $e');
      }

      final currentPaid = (invoiceData['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = totalPaidFromTxs > 0 ? totalPaidFromTxs : currentPaid;

      // 5. Update the purchase invoice
      final remainingAmount = (netAmount - totalPaid).clamp(0.0, double.infinity);
      final String paymentStatus;
      if (remainingAmount <= 0.001) {
        paymentStatus = 'paid';
      } else if (totalPaid > 0.001) {
        paymentStatus = 'partial';
      } else {
        paymentStatus = 'unpaid';
      }

      await _client.from('purchase_invoices').update({
        'paid_amount': totalPaid,
        'remaining_amount': remainingAmount,
        'payment_status': paymentStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', idVal);

      debugPrint('✅ PurchaseInvoiceService.recalculate: invoice $idVal updated -> paid=$totalPaid, remaining=$remainingAmount, status=$paymentStatus');
    } catch (e) {
      debugPrint('⚠️ PurchaseInvoiceService.recalculate error: $e');
    }
  }
}
