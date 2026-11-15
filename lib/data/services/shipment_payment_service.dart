import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dao/bank_account_dao.dart';
import '../dao/transaction_dao.dart';
import '../models/export_shipment_model.dart';
import 'chart_of_accounts_service.dart';
import 'currency_conversion_service.dart';

/// Processes customer payment deposits for export shipments.
///
/// When a shipment is saved with paidAmount > 0, the money is DEPOSITED
/// into the selected treasury/bank account (opposite of purchases which
/// deduct from treasury/bank).
///
/// - Treasury source → calls TreasuryDao.deposit() (adds balance)
/// - Bank source → calls BankAccountDao.depositWithCounterparty() (adds balance)
/// - GL entries: Dr. treasury/bank, Cr. 1000 (customer receivable)
class ShipmentPaymentService {
  static const _tag = 'ShipmentPaymentService';
  void _log(String msg) => debugPrint('$_tag: $msg');

  final _client = Supabase.instance.client;

  /// Process payment delta for an export shipment.
  Future<void> processPayment({
    required ExportShipmentModel shipment,
    String? customerName,
    double oldPaidAmount = 0,
    String? oldPaymentSourceType,
    String? oldPaymentTreasuryId,
    int? oldPaymentBankAccountId,
  }) async {
    final newPaid = shipment.paidAmount;
    final delta = newPaid - oldPaidAmount;

    if (delta == 0) return;
    if (shipment.customerId == null || shipment.customerId!.isEmpty) {
      _log('Skipping payment: no customer');
      return;
    }

    final name = customerName ?? shipment.customerName ?? '';
    final paymentType = _paymentTypeLabel(shipment.paymentSourceType);
    final desc = buildDescription(
      paymentType: paymentType,
      shipmentNo: shipment.shipmentNo,
      customerName: name,
    );
    final reverseDesc = buildReversalDescription(
      paymentType: paymentType,
      shipmentNo: shipment.shipmentNo,
      customerName: name,
    );

    try {
      if (delta > 0) {
        await _depositPayment(
          shipment: shipment,
          amount: delta,
          description: desc,
        );
      } else {
        await _reverseDeposit(
          amount: delta.abs(),
          sourceType: oldPaymentSourceType ?? shipment.paymentSourceType,
          treasuryId: oldPaymentTreasuryId ?? shipment.paymentTreasuryId,
          bankAccountId: oldPaymentBankAccountId ?? shipment.paymentBankAccountId,
          currency: shipment.currencyCode,
          description: reverseDesc,
          customerName: name,
          customerId: shipment.customerId,
        );
      }
    } catch (e, st) {
      _log('Payment processing failed (non-fatal): $e\n$st');
    }
  }

  /// Builds a unified description for shipment payments.
  static String buildDescription({
    required String paymentType,
    required String shipmentNo,
    required String customerName,
  }) {
    return 'إيداع $paymentType مقابل شحنة تصديرية رقم $shipmentNo - من العميل $customerName (سداد حساب العميل)';
  }

  static String buildReversalDescription({
    required String paymentType,
    required String shipmentNo,
    required String customerName,
  }) {
    return 'استرداد إيداع $paymentType مقابل شحنة تصديرية رقم $shipmentNo - للعميل $customerName';
  }

  static String _paymentTypeLabel(String? sourceType) {
    switch (sourceType) {
      case 'bank':
        return 'تحويل بنكي';
      case 'treasury':
      default:
        return 'نقدي';
    }
  }

  /// Deposit into treasury or bank (money comes IN from customer)
  Future<void> _depositPayment({
    required ExportShipmentModel shipment,
    required double amount,
    required String description,
  }) async {
    // Idempotency check: prevent duplicate deposit if already recorded for this shipment
    final sid = shipment.id;
    final shipmentNo = shipment.shipmentNo;
    if (sid != null && sid.isNotEmpty) {
      try {
        final existingJes = await _client
            .from('journal_entries')
            .select('id')
            .inFilter('source_type', [
              'bank_deposit', 'customer_bank_deposit',
              'customer_treasury_deposit', 'export_payment',
            ])
            .or('source_id.eq.$sid,description.ilike.%$shipmentNo%')
            .limit(1);

        if (existingJes.isNotEmpty) {
          _log('Payment already recorded for shipment $shipmentNo, ensuring source_id is stamped');
          await _client.from('journal_entries')
              .update({'source_id': sid})
              .ilike('description', '%$shipmentNo%')
              .inFilter('source_type', [
                'bank_deposit', 'customer_bank_deposit',
                'customer_treasury_deposit', 'export_payment',
              ]);
          return;
        }
      } catch (e) {
        _log('Idempotency check warning: $e');
      }
    }

    // Delete any existing legacy payment ledger entries for this shipment to prevent duplicates
    final customerId = int.tryParse(shipment.customerId ?? '');
    if (customerId != null) {
      await _client.from('ledger_entries').delete()
          .eq('entity_type', 'customer')
          .eq('entity_id', customerId.toString())
          .inFilter('reference_type', ['bank_transfer', 'treasury_deposit', 'payment'])
          .like('description', '%$shipmentNo%');
    }

    if (shipment.paymentSourceType == 'treasury' && shipment.paymentTreasuryId != null) {
      _log('Depositing to treasury: ${shipment.paymentTreasuryId} ${shipment.currencyCode} $amount');
      final cid = int.tryParse(shipment.customerId ?? '');
      if (cid != null) {
        await _client.rpc('rpc_deposit_customer_treasury', params: {
          'p_treasury_id': shipment.paymentTreasuryId!,
          'p_currency': shipment.currencyCode,
          'p_amount': amount,
          'p_description': description,
          'p_customer_id': cid,
        });

        // Stamp source_id on the generated journal entry
        if (sid != null) {
          await _client.from('journal_entries')
              .update({'source_id': sid})
              .ilike('description', '%$shipmentNo%')
              .eq('source_type', 'customer_treasury_deposit');
        }
      }
      _log('Treasury deposit OK');
    } else if (shipment.paymentSourceType == 'bank' && shipment.paymentBankAccountId != null) {
      _log('Depositing to bank: ${shipment.paymentBankAccountId} ${shipment.currencyCode} $amount');
      // SQL function deposit_bank_account creates the official GL journal entry and updates balances atomically
      await BankAccountDao().depositWithCounterparty(
        accountId: shipment.paymentBankAccountId!,
        amount: amount,
        description: description,
        counterpartyType: 'customer',
        counterpartyId: int.tryParse(shipment.customerId ?? ''),
        counterpartyName: shipment.customerName,
        referenceText: shipment.shipmentNo,
      );

      // Stamp source_id on the generated bank deposit journal entry
      if (sid != null) {
        await _client.from('journal_entries')
            .update({'source_id': sid})
            .ilike('description', '%$shipmentNo%')
            .inFilter('source_type', ['bank_deposit', 'customer_bank_deposit']);
      }

      _log('Bank deposit OK');
    }
  }

  /// Reverse a deposit (refund back)
  Future<void> _reverseDeposit({
    required double amount,
    required String? sourceType,
    required String? treasuryId,
    required int? bankAccountId,
    required String currency,
    required String description,
    required String customerName,
    String? customerId,
  }) async {
    _log('Reversing deposit: $amount via $sourceType');

    if (sourceType == 'treasury' && treasuryId != null) {
      final cid = int.tryParse(customerId ?? '');
      if (cid != null) {
        await _client.rpc('rpc_withdraw_customer_treasury', params: {
          'p_treasury_id': int.tryParse(treasuryId) ?? 0,
          'p_currency': currency,
          'p_amount': amount,
          'p_description': description,
          'p_customer_id': cid,
        });
      }
    } else if (sourceType == 'bank' && bankAccountId != null) {
      await BankAccountDao().withdrawWithCounterparty(
        accountId: bankAccountId,
        amount: amount,
        description: description,
        counterpartyType: 'customer',
        counterpartyName: customerName,
      );
    }

    _log('Reversal OK');
  }
}
