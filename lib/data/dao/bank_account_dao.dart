import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bank_account_model.dart';
import '../models/bank_account_transaction_model.dart';
import '../services/currency_conversion_service.dart';
import '../../core/extensions/company_injection.dart';


class BankAccountDao {
  final _client = Supabase.instance.client;

  static const _defaults = [
    {'name': 'الجنيه المصري', 'name_en': 'Egyptian Pound', 'currency': 'EGP'},
    {'name': 'الدولار الأمريكي', 'name_en': 'US Dollar', 'currency': 'USD'},
    {'name': 'اليورو', 'name_en': 'Euro', 'currency': 'EUR'},
    {'name': 'الجنيه الإسترليني', 'name_en': 'British Pound', 'currency': 'GBP'},
  ];

  Future<List<BankAccountModel>> getAll() async {
    var data = await _client
        .from('bank_accounts')
        .select()
        .order('id');
    if ((data as List).isEmpty) {
      await _seedDefaults();
      data = await _client
          .from('bank_accounts')
          .select()
          .order('id');
    }
    return (data as List)
        .map((e) => BankAccountModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _seedDefaults() async {
    try {
      final maps = _defaults.map((e) => Map<String, dynamic>.from(e)).toList();
      await _client.from('bank_accounts').upsert(
        maps.withCompanyId(),
        onConflict: 'currency',
      );
      debugPrint('✅ Bank accounts seeded');
    } catch (e) {
      debugPrint('⚠️ Bank account seed failed: $e');
    }
  }

  Future<BankAccountModel?> getById(int id) async {
    final data = await _client
        .from('bank_accounts')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return BankAccountModel.fromMap(Map<String, dynamic>.from(data));
  }

  Future<void> _stampLatestTransactionSnapshot(int accountId, String currency, double amount) async {
    try {
      final latest = await _client
          .from('bank_account_transactions')
          .select('id')
          .eq('bank_account_id', accountId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (latest != null) {
        await _client.from('bank_account_transactions').update({
          'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
            currency: currency,
            amount: amount,
            exchangeRate: 1.0,
          ).toJson(),
        }).eq('id', latest['id']);
      }
    } catch (e) {
      debugPrint('⚠️ _stampLatestTransactionSnapshot error: $e');
    }
  }

  Future<void> deposit({
    required int accountId,
    required double amount,
    String? description,
    int? revenueAccountId,
    String? notes,
  }) async {
    await _client.rpc('deposit_bank_account', params: {
      'p_account_id': accountId,
      'p_amount': amount,
      'p_description': description,
      'p_entity_type': null,
      'p_entity_id': null,
      'p_counterparty_name': null,
      'p_revenue_account_id': revenueAccountId,
      'p_source_type': revenueAccountId != null ? 'revenue' : 'opening_balance',
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
    });
    final acc = await _client.from('bank_accounts').select('currency').eq('id', accountId).maybeSingle();
    await _stampLatestTransactionSnapshot(accountId, acc?['currency'] ?? 'EGP', amount);
  }

  Future<void> depositWithCounterparty({
    required int accountId,
    required double amount,
    String? description,
    String? counterpartyType,
    int? counterpartyId,
    String? supplierId,
    String? shareholderId,
    String? counterpartyName,
    String? referenceText,
    int? revenueAccountId,
    String? notes,
  }) async {
    // 1. Deposit into bank account + party balance + ledger_entries (one SQL transaction)
    await _client.rpc('deposit_bank_account', params: {
      'p_account_id': accountId,
      'p_amount': amount,
      'p_description': description,
      'p_entity_type': counterpartyType,
      'p_entity_id': counterpartyId?.toString() ?? supplierId ?? shareholderId,
      'p_counterparty_name': counterpartyName,
      'p_revenue_account_id': revenueAccountId,
      'p_source_type': counterpartyType ?? (revenueAccountId != null ? 'revenue' : 'deposit'),
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
    });

    // 2. Stamp currency_snapshot on the latest bank_account_transactions row
    final acc = await _client.from('bank_accounts').select('currency').eq('id', accountId).maybeSingle();
    await _stampLatestTransactionSnapshot(accountId, acc?['currency'] ?? 'EGP', amount);
  }

  Future<void> withdraw({
    required int accountId,
    required double amount,
    String? description,
    int? expenseAccountId,
    String? notes,
  }) async {
    await _client.rpc('withdraw_bank_account', params: {
      'p_account_id': accountId,
      'p_amount': amount,
      'p_description': description,
      'p_entity_type': null,
      'p_entity_id': null,
      'p_counterparty_name': null,
      'p_expense_account_id': expenseAccountId,
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
    });
    final acc = await _client.from('bank_accounts').select('currency').eq('id', accountId).maybeSingle();
    await _stampLatestTransactionSnapshot(accountId, acc?['currency'] ?? 'EGP', amount);
  }

  Future<void> withdrawWithCounterparty({
    required int accountId,
    required double amount,
    String? description,
    String? counterpartyType,
    int? counterpartyId,
    String? supplierId,
    String? shareholderId,
    String? counterpartyName,
    int? expenseAccountId,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    // 1. Withdraw from bank account + party balance + ledger_entries (one SQL transaction)
    await _client.rpc('withdraw_bank_account', params: {
      'p_account_id': accountId,
      'p_amount': amount,
      'p_description': description,
      'p_entity_type': counterpartyType,
      'p_entity_id': counterpartyId?.toString() ?? supplierId ?? shareholderId,
      'p_counterparty_name': counterpartyName,
      'p_expense_account_id': expenseAccountId,
      'p_reference_type': referenceType,
      'p_reference_id': referenceId,
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
    });

    // 2. Stamp currency_snapshot on the latest bank_account_transactions row
    final acc = await _client.from('bank_accounts').select('currency').eq('id', accountId).maybeSingle();
    await _stampLatestTransactionSnapshot(accountId, acc?['currency'] ?? 'EGP', amount);
  }

  Future<List<BankAccountTransactionModel>> getTransactions(
    int accountId, {
    int limit = 200,
    DateTime? startDate,
    DateTime? endDate,
    Map<String, String>? userNamesCache,
  }) async {
    var query = _client
        .from('bank_account_transactions')
        .select('*, journal_entry_id')
        .eq('bank_account_id', accountId);

    if (startDate != null) {
      query = query.gte('created_at', startDate.toUtc().toIso8601String());
    }
    if (endDate != null) {
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59).toUtc();
      query = query.lte('created_at', end.toIso8601String());
    }

    final data = await query.order('created_at', ascending: false).limit(limit);

    final userIds = (data as List)
        .map((m) => (m as Map<String, dynamic>)['created_by']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .toList();

    Map<String, String> userNames = userNamesCache ?? {};
    if (userIds.isNotEmpty && userNamesCache == null) {
      try {
        final users = await _client.from('users').select('id, full_name').inFilter('id', userIds);
        for (final u in (users as List)) {
          final m = Map<String, dynamic>.from(u);
          userNames[m['id'].toString()] = (m['full_name'] ?? '').toString();
        }
      } catch (_) {}
    }

    return (data as List)
        .map((m) {
          final map = Map<String, dynamic>.from(m);
          final cbId = map['created_by']?.toString();
          if (cbId != null && userNames.containsKey(cbId)) {
            map['created_by_user'] = {'full_name': userNames[cbId]};
          }
          return BankAccountTransactionModel.fromMap(map);
        })
        .toList();
  }

  Future<void> updateTransaction({
    required int transactionId,
    required double newAmount,
    String? newDescription,
    String? newType,
  }) async {
    try {
      await _client.rpc('update_bank_account_transaction', params: {
        'p_transaction_id': transactionId,
        'p_new_amount': newAmount,
        'p_new_description': newDescription,
      });
    } catch (rpcError) {
      debugPrint('update_bank_account_transaction RPC error, running direct fallback: $rpcError');
      final tx = await _client
          .from('bank_account_transactions')
          .select('id, bank_account_id, type, amount, balance_after')
          .eq('id', transactionId)
          .maybeSingle();

      if (tx != null) {
        final bankAccId = tx['bank_account_id'] is int
            ? tx['bank_account_id'] as int
            : int.tryParse(tx['bank_account_id']?.toString() ?? '') ?? 0;
        final oldAmount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final txType = newType ?? (tx['type']?.toString() ?? '');
        final diff = newAmount - oldAmount;

        final isDeposit = txType == 'deposit' || txType == 'currency_exchange_in';
        final balanceDiff = isDeposit ? diff : -diff;

        final bankAcc = await _client
            .from('bank_accounts')
            .select('balance')
            .eq('id', bankAccId)
            .maybeSingle();

        if (bankAcc != null) {
          final currentBal = (bankAcc['balance'] as num).toDouble();
          final newBal = currentBal + balanceDiff;
          if (newBal < 0) {
            throw Exception('الرصيد غير كافٍ في الحساب البنكي (المتوفر: ${currentBal.toStringAsFixed(2)})');
          }
          await _client
              .from('bank_accounts')
              .update({'balance': newBal})
              .eq('id', bankAccId);
        }

        final txUpdates = <String, dynamic>{
          'amount': newAmount,
          'balance_after': ((tx['balance_after'] as num?)?.toDouble() ?? 0.0) + balanceDiff,
        };
        if (newDescription != null) txUpdates['description'] = newDescription;
        if (newType != null) txUpdates['type'] = newType;
        await _client
            .from('bank_account_transactions')
            .update(txUpdates)
            .eq('id', transactionId);
      } else {
        rethrow;
      }
    }

    // Synchronize GL / Journal Entry if linked
    try {
      final txRow = await _client
          .from('bank_account_transactions')
          .select('journal_entry_id')
          .eq('id', transactionId)
          .maybeSingle();

      final jeId = txRow?['journal_entry_id'];
      if (jeId != null) {
        if (newDescription != null && newDescription.isNotEmpty) {
          await _client.from('journal_entries').update({
            'description': newDescription,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', jeId);
        }

        final lines = await _client
            .from('account_ledger_entries')
            .select('id, debit, credit')
            .eq('journal_entry_id', jeId);

        for (final line in lines) {
          final lineId = line['id'];
          final oldDebit = (line['debit'] as num?)?.toDouble() ?? 0.0;
          final oldCredit = (line['credit'] as num?)?.toDouble() ?? 0.0;
          final updates = <String, dynamic>{};
          if (oldDebit > 0) {
            updates['debit'] = newAmount;
            updates['amount_in_base_currency'] = newAmount;
          } else if (oldCredit > 0) {
            updates['credit'] = newAmount;
            updates['amount_in_base_currency'] = newAmount;
          }
          if (newDescription != null && newDescription.isNotEmpty) {
            updates['description'] = newDescription;
          }
          if (updates.isNotEmpty) {
            await _client.from('account_ledger_entries').update(updates).eq('id', lineId);
          }
        }
      }
    } catch (glError) {
      debugPrint('BankAccountDao: error syncing GL for tx $transactionId: $glError');
    }
  }

  Future<void> deleteTransaction({required int transactionId}) async {
    await _client.rpc('delete_bank_account_transaction', params: {
      'p_transaction_id': transactionId,
    });
  }

  Future<void> transferFunds({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    String? description,
    double bankFee = 0.0,
    String? notes,
  }) async {
    await _client.rpc('bank_transfer', params: {
      'p_from_account_id': fromAccountId,
      'p_to_account_id': toAccountId,
      'p_amount': amount,
      'p_description': description,
      'p_bank_fee': bankFee,
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
    });
  }

  Future<void> exchangeCurrency({
    required int fromAccountId,
    required int toAccountId,
    required double amountFrom,
    required double amountTo,
    required double exchangeRate,
    double bankFee = 0.0,
    String transferMode = 'exchange',
  }) async {
    await _client.rpc('exchange_bank_currency', params: {
      'p_from_account_id': fromAccountId,
      'p_to_account_id': toAccountId,
      'p_amount_from': amountFrom,
      'p_amount_to': amountTo,
      'p_exchange_rate': exchangeRate,
      'p_bank_fee': bankFee,
      'p_transfer_mode': transferMode,
    });
  }

  // ── Draft Workflow ──

  Future<int> saveDraft({
    required int bankAccountId,
    required String type,
    required double amount,
    String? description,
    String? notes,
    String? entityType,
    String? entityId,
    String? counterpartyName,
    Map<String, dynamic> payload = const {},
  }) async {
    final result = await _client.rpc('rpc_save_bank_draft', params: {
      'p_bank_account_id': bankAccountId,
      'p_type': type,
      'p_amount': amount,
      'p_description': description,
      'p_notes': notes,
      'p_entity_type': entityType,
      'p_entity_id': entityId,
      'p_counterparty_name': counterpartyName,
      'p_payload': payload,
    });
    return result is int ? result : int.tryParse('$result') ?? 0;
  }

  Future<void> updateDraft({
    required int transactionId,
    int? bankAccountId,
    String? type,
    double? amount,
    String? description,
    String? notes,
    String? entityType,
    String? entityId,
    String? counterpartyName,
    Map<String, dynamic>? payload,
  }) async {
    await _client.rpc('rpc_update_bank_draft', params: {
      'p_transaction_id': transactionId,
      if (bankAccountId != null) 'p_bank_account_id': bankAccountId,
      if (type != null) 'p_type': type,
      if (amount != null) 'p_amount': amount,
      'p_description': description,
      'p_notes': notes,
      'p_entity_type': entityType,
      'p_entity_id': entityId,
      'p_counterparty_name': counterpartyName,
      if (payload != null) 'p_payload': payload,
    });
  }

  Future<void> deleteDraft({required int transactionId}) async {
    await _client.rpc('rpc_delete_bank_draft', params: {
      'p_transaction_id': transactionId,
    });
  }

  Future<Map<String, dynamic>> confirmDraft({required int transactionId}) async {
    final result = await _client.rpc('rpc_confirm_bank_draft', params: {
      'p_transaction_id': transactionId,
    });
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'success': true};
  }
}
