import 'package:flutter/foundation.dart';
import '../dao/treasury_dao.dart';
import '../dao/bank_account_dao.dart';
import '../models/lot_model.dart';
import '../models/purchase_model.dart';

/// Processes treasury/bank payments + GL journal entries when a lot receipt
/// is saved with paidAmount > 0.
///
/// - Treasury source → calls TreasuryDao.spend() (deducts balance, supplier
///   outstanding, creates GL entries)
/// - Bank source → calls BankAccountDao.withdrawWithCounterparty() (deducts
///   balance, supplier outstanding, ledger entries)
class LotPaymentService {
  static const _tag = 'LotPaymentService';
  void _log(String msg) => debugPrint('$_tag: $msg');

  /// Builds a unified transaction description following the standard format:
  /// "دفعة [نوع] لشراء محصول [المحصول] - لوت رقم [X] - من المورد [اسم]"
  ///
  /// Only includes parts that have actual data — no placeholders.
  static String buildDescription({
    required String paymentType,
    required String productName,
    required String lotNumber,
    required String supplierName,
  }) {
    final parts = <String>[
      'دفعة',
      paymentType,
      'لشراء محصول',
      productName,
      '- لوت رقم',
      lotNumber,
      '- من المورد',
      supplierName,
    ];
    return parts.join(' ');
  }

  /// Builds a reversal description following the same standard format.
  static String buildReversalDescription({
    required String paymentType,
    required String productName,
    required String lotNumber,
    required String supplierName,
  }) {
    final parts = <String>[
      'استرداد دفعة',
      paymentType,
      'لشراء محصول',
      productName,
      '- لوت رقم',
      lotNumber,
      '- من المورد',
      supplierName,
    ];
    return parts.join(' ');
  }

  /// Maps payment source type to Arabic label.
  static String _paymentTypeLabel(String? sourceType) {
    switch (sourceType) {
      case 'bank':
        return 'تحويل بنكي';
      case 'treasury':
      default:
        return 'نقدي';
    }
  }

  /// Process payment delta for a lot receipt.
  Future<void> processPayment({
    required LotReceiptModel lot,
    String? supplierName,
    double oldPaidAmount = 0,
    String? oldPaymentSourceType,
    String? oldPaymentTreasuryId,
    int? oldPaymentBankAccountId,
  }) async {
    final newPaid = lot.paidAmount;
    final delta = newPaid - oldPaidAmount;

    if (delta == 0) return;
    if (lot.supplierId == null || lot.supplierId!.isEmpty) {
      _log('Skipping payment: no supplier');
      return;
    }

    final supplierId = lot.supplierId!;
    final paymentType = _paymentTypeLabel(lot.paymentSourceType);
    final name = supplierName ?? '';

    final description = buildDescription(
      paymentType: paymentType,
      productName: lot.productName ?? '',
      lotNumber: lot.lotNumber,
      supplierName: name,
    );

    final reverseDescription = buildReversalDescription(
      paymentType: paymentType,
      productName: lot.productName ?? '',
      lotNumber: lot.lotNumber,
      supplierName: name,
    );

    try {
      if (delta > 0) {
        await _createPayment(
          lot: lot,
          amount: delta,
          supplierId: supplierId,
          supplierName: name,
          description: description,
        );
      } else {
        await _reversePayment(
          amount: delta.abs(),
          sourceType: oldPaymentSourceType ?? lot.paymentSourceType,
          treasuryId: oldPaymentTreasuryId ?? lot.paymentTreasuryId,
          bankAccountId: oldPaymentBankAccountId ?? lot.paymentBankAccountId,
          supplierId: supplierId,
          supplierName: name,
          currency: lot.currency,
          description: reverseDescription,
        );
      }
    } catch (e, st) {
      _log('Payment processing failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> _createPayment({
    required LotReceiptModel lot,
    required double amount,
    required String supplierId,
    required String supplierName,
    required String description,
  }) async {
    if (lot.paymentSourceType == 'treasury' && lot.paymentTreasuryId != null) {
      await _payFromTreasury(
        treasuryId: lot.paymentTreasuryId!,
        currency: lot.currency,
        amount: amount,
        supplierId: supplierId,
        description: description,
        lotId: lot.id ?? lot.lotNumber,
      );
    } else if (lot.paymentSourceType == 'bank' && lot.paymentBankAccountId != null) {
      await _payFromBank(
        bankAccountId: lot.paymentBankAccountId!,
        currency: lot.currency,
        amount: amount,
        supplierId: supplierId,
        supplierName: supplierName,
        description: description,
        lotId: lot.id ?? lot.lotNumber,
      );
    }
  }

  Future<void> _payFromTreasury({
    required String treasuryId,
    required String currency,
    required double amount,
    required String supplierId,
    required String description,
    String? lotId,
  }) async {
    _log('Paying from treasury: $treasuryId $currency $amount');
    await TreasuryDao().spend(
      treasuryId: treasuryId,
      currency: currency,
      amount: amount,
      description: description,
      ledgerDescription: description,
      supplierId: supplierId,
      invoice: lotId != null
          ? PurchaseModel(
              id: 'lot_$lotId',
              purchaseNumber: lotId,
              purchaseDate: DateTime.now().toIso8601String(),
              createdAt: DateTime.now().toIso8601String(),
              notes: 'crop_lot',
            )
          : null,
    );
    _log('Treasury payment OK');
  }

  Future<void> _payFromBank({
    required int bankAccountId,
    required String currency,
    required double amount,
    required String supplierId,
    required String supplierName,
    required String description,
    String? lotId,
  }) async {
    _log('Paying from bank: $bankAccountId $currency $amount');
    await BankAccountDao().withdrawWithCounterparty(
      accountId: bankAccountId,
      amount: amount,
      description: description,
      counterpartyType: 'supplier',
      supplierId: supplierId,
      counterpartyName: supplierName,
      referenceType: lotId != null ? 'lot_receipt' : null,
      referenceId: lotId,
    );

    _log('Bank payment OK');
  }

  Future<void> _reversePayment({
    required double amount,
    required String? sourceType,
    required String? treasuryId,
    required int? bankAccountId,
    required String supplierId,
    required String supplierName,
    required String currency,
    required String description,
  }) async {
    _log('Reversing payment: $amount via $sourceType');

    if (sourceType == 'treasury' && treasuryId != null) {
      await TreasuryDao().deposit(
        treasuryId: treasuryId,
        currency: currency,
        amount: amount,
        description: description,
      );
    } else if (sourceType == 'bank' && bankAccountId != null) {
      await BankAccountDao().depositWithCounterparty(
        accountId: bankAccountId,
        amount: amount,
        description: description,
        counterpartyType: 'supplier',
        supplierId: supplierId,
        counterpartyName: supplierName,
      );
    }

    _log('Reversal OK');
  }
}
