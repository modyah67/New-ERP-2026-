import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/treasury_dao.dart';
import '../dao/bank_account_dao.dart';

/// Processes treasury/bank payments + GL journal entries when a purchase invoice
/// is saved with paidAmount > 0 (like the lot form pattern).
///
/// - Treasury source → calls TreasuryDao.spend()
/// - Bank source → calls BankAccountDao.withdrawWithCounterparty()
class PurchasePaymentService {
  static const _tag = 'PurchasePaymentService';
  void _log(String msg) => debugPrint('$_tag: $msg');

  final _client = Supabase.instance.client;

  /// Build description following unified format.
  static String buildDescription({
    required String sourceName,
    required String invoiceNumber,
  }) {
    return 'دفعة للمورد - فاتورة رقم $invoiceNumber - من $sourceName';
  }

  /// Process payment for a purchase invoice (initial save).
  Future<void> processPayment({
    required double amount,
    required String supplierId,
    required String currency,
    required String invoiceNumber,
    String? sourceType,
    String? treasuryId,
    int? bankAccountId,
  }) async {
    if (amount <= 0) return;
    if (supplierId.isEmpty) {
      _log('Skipping payment: no supplier');
      return;
    }

    final effectiveSourceType = sourceType ?? 'treasury';

    _log('Processing payment: $amount $currency via $effectiveSourceType');

    if (effectiveSourceType == 'bank' && bankAccountId != null) {
      await _payFromBank(
        bankAccountId: bankAccountId,
        currency: currency,
        amount: amount,
        supplierId: supplierId,
        invoiceNumber: invoiceNumber,
      );
    } else if (effectiveSourceType == 'treasury' && treasuryId != null) {
      await _payFromTreasury(
        treasuryId: treasuryId,
        currency: currency,
        amount: amount,
        supplierId: supplierId,
        invoiceNumber: invoiceNumber,
      );
    } else {
      _log('No valid payment source: sourceType=$effectiveSourceType treasuryId=$treasuryId bankAccountId=$bankAccountId');
    }
  }

  /// Process delta payment for an existing purchase invoice (edit).
  /// Handles both additional payments and reversals.
  Future<void> processPaymentDelta({
    required double newPaidAmount,
    required double oldPaidAmount,
    required String supplierId,
    required String currency,
    required String invoiceNumber,
    String? newSourceType,
    String? newTreasuryId,
    int? newBankAccountId,
    String? oldSourceType,
    String? oldTreasuryId,
    int? oldBankAccountId,
  }) async {
    final delta = newPaidAmount - oldPaidAmount;
    if (delta == 0) return;

    _log('Delta payment: delta=$delta (new=$newPaidAmount old=$oldPaidAmount)');

    if (delta > 0) {
      // Additional payment
      await processPayment(
        amount: delta,
        supplierId: supplierId,
        currency: currency,
        invoiceNumber: invoiceNumber,
        sourceType: newSourceType,
        treasuryId: newTreasuryId,
        bankAccountId: newBankAccountId,
      );
    } else {
      // Reversal
      await _reversePayment(
        amount: delta.abs(),
        sourceType: oldSourceType ?? newSourceType,
        treasuryId: oldTreasuryId ?? newTreasuryId,
        bankAccountId: oldBankAccountId ?? newBankAccountId,
        supplierId: supplierId,
        currency: currency,
        invoiceNumber: invoiceNumber,
      );
    }
  }

  Future<void> _payFromTreasury({
    required String treasuryId,
    required String currency,
    required double amount,
    required String supplierId,
    required String invoiceNumber,
  }) async {
    final sourceName = await _resolveTreasuryName(treasuryId);
    final description = buildDescription(sourceName: sourceName, invoiceNumber: invoiceNumber);

    _log('Paying from treasury: $treasuryId $currency $amount');
    await TreasuryDao().spend(
      treasuryId: treasuryId,
      currency: currency,
      amount: amount,
      description: description,
      ledgerDescription: description,
      supplierId: supplierId,
    );
    _log('Treasury payment OK');
  }

  Future<void> _payFromBank({
    required int bankAccountId,
    required String currency,
    required double amount,
    required String supplierId,
    required String invoiceNumber,
  }) async {
    final bankName = await _resolveBankName(bankAccountId);
    final description = buildDescription(sourceName: bankName, invoiceNumber: invoiceNumber);

    _log('Paying from bank: $bankAccountId $currency $amount');
    await BankAccountDao().withdrawWithCounterparty(
      accountId: bankAccountId,
      amount: amount,
      description: description,
      counterpartyType: 'supplier',
      supplierId: supplierId,
      counterpartyName: bankName,
    );

    _log('Bank payment OK');
  }

  Future<void> _reversePayment({
    required double amount,
    required String? sourceType,
    required String? treasuryId,
    required int? bankAccountId,
    required String supplierId,
    required String currency,
    required String invoiceNumber,
  }) async {
    _log('Reversing payment: $amount via $sourceType');

    if (sourceType == 'treasury' && treasuryId != null) {
      final sourceName = await _resolveTreasuryName(treasuryId);
      final description = 'استرداد دفعة - فاتورة رقم $invoiceNumber - من $sourceName';
      await TreasuryDao().deposit(
        treasuryId: treasuryId,
        currency: currency,
        amount: amount,
        description: description,
      );
    } else if (sourceType == 'bank' && bankAccountId != null) {
      final bankName = await _resolveBankName(bankAccountId);
      final description = 'استرداد دفعة - فاتورة رقم $invoiceNumber - من $bankName';
      await BankAccountDao().depositWithCounterparty(
        accountId: bankAccountId,
        amount: amount,
        description: description,
        counterpartyType: 'supplier',
        supplierId: supplierId,
        counterpartyName: bankName,
      );
    }

    _log('Reversal OK');
  }

  Future<String> _resolveTreasuryName(String treasuryId) async {
    try {
      final row = await _client
          .from('treasuries')
          .select('name')
          .eq('id', int.tryParse(treasuryId) ?? 0)
          .maybeSingle();
      return row?['name'] ?? 'الخزينة';
    } catch (_) {
      return 'الخزينة';
    }
  }

  Future<String> _resolveBankName(int bankAccountId) async {
    try {
      final row = await _client
          .from('bank_accounts')
          .select('name')
          .eq('id', bankAccountId)
          .maybeSingle();
      return row?['name'] ?? 'البنك';
    } catch (_) {
      return 'البنك';
    }
  }
}
