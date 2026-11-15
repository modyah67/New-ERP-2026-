import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../accounting/fiscal_year/dao/fiscal_year_dao.dart';
import '../../core/utils.dart';
import '../models/transaction_model.dart';
import '../services/currency_conversion_service.dart';

class TransactionDao {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  static const _selectWithEmbeds = '*';

  final Map<String, Map<String, String>> _accountsCache = {};

  TransactionModel _flattenRow(dynamic e) {
    final row =
        e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map);
    row.remove('accounts');

    final debit = (row['debit'] as num?)?.toDouble() ?? 0.0;
    final credit = (row['credit'] as num?)?.toDouble() ?? 0.0;
    final amount = debit > 0 ? debit : credit;
    final type = debit > 0 ? 'debit' : 'credit';

    final accId = row['account_id']?.toString();
    final accInfo = accId != null ? _accountsCache[accId] : null;

    return TransactionModel.fromMap({
      ...row,
      'amount': amount,
      'type': type,
      'account_name': accInfo?['name'],
      'account_code': accInfo?['code'],
    });
  }

  Future<void> _preloadAccounts(List<dynamic> data) async {
    final ids = <String>{};
    for (final row in data) {
      final m = row is Map<String, dynamic> ? row : Map<String, dynamic>.from(row as Map);
      if (m['account_id'] != null) ids.add(m['account_id'].toString());
    }
    if (ids.isEmpty) return;
    try {
      final accData = await _client
          .from('accounts')
          .select('id, name, account_code')
          .inFilter('id', ids.toList());
      for (final a in (accData as List)) {
        final m = Map<String, dynamic>.from(a as Map);
        _accountsCache[m['id'].toString()] = {
          'name': (m['name'] ?? '').toString(),
          'code': (m['account_code'] ?? m['code'] ?? '').toString(),
        };
      }
    } catch (_) {}
  }

  Future<List<TransactionModel>> getAll({
    String? customerId,
    String? fromDate,
    String? toDate,
    int? limit,
    int? offset,
  }) async {
    var query = _client.from('transactions').select(_selectWithEmbeds);

    if (customerId != null) {
      query = query.eq('customer_id', customerId);
    }
    if (fromDate != null) {
      query = query.gte('transaction_date', fromDate);
    }
    if (toDate != null) {
      query = query.lte('transaction_date', toDate);
    }

    if (limit != null) {
      final from = offset ?? 0;
      final data = await query
          .order('transaction_date', ascending: false)
          .order('id', ascending: false)
          .range(from, from + limit - 1);
      await _preloadAccounts(data);
      return data.map(_flattenRow).toList();
    }

    final data = await query
        .order('transaction_date', ascending: false)
        .order('id', ascending: false);
    await _preloadAccounts(data);
    return data.map(_flattenRow).toList();
  }

  Future<int> insert(TransactionModel transaction,
      {String? referenceType, String? referenceId}) async {
    final data = await _client
        .from('transactions')
        .insert({
          'entry_number': transaction.entryNumber,
          'transaction_date': transaction.transactionDate,
          'account_id': transaction.accountId,
          'debit': transaction.type == 'debit' ? transaction.amount : 0,
          'credit': transaction.type == 'credit' ? transaction.amount : 0,
          'description': transaction.description,
          'reference_type': referenceType ??
              (transaction.invoiceId != null
                  ? 'invoice'
                  : (transaction.purchaseId != null ? 'purchase' : null)),
          'reference_id': referenceId ??
              transaction.invoiceId?.toString() ??
              transaction.purchaseId?.toString(),
          'created_by': _userId,
          'currency_snapshot': CurrencyConversionService.instance
              .createSnapshot(
                currency: 'EGP',
                amount: transaction.amount,
                exchangeRate: 1.0,
              )
              .toJson(),
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<int> getNextEntryNumber() async {
    try {
      final result = await _client.rpc('get_next_entry_number');
      if (result is String) {
        final parsed = int.tryParse(result.replaceFirst('J', ''));
        if (parsed != null) return parsed;
      }
      return 1;
    } catch (e) {
      debugPrint('TransactionDao.getNextEntryNumber error: $e');
      return 1;
    }
  }

  /// Creates a balanced journal entry (debit + credit) atomically via RPC.
  /// Returns the entry_number.
  Future<String> insertBalancedEntry({
    required String debitAccountId,
    required String creditAccountId,
    required double amount,
    String? description,
    String? transactionDate,
    String? referenceType,
    String? referenceId,
    Map<String, dynamic>? currencySnapshot,
  }) async {
    final dateStr = transactionDate ?? DateTime.now().toIso8601String().substring(0, 10);
    final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    final isClosed = await FiscalYearDao().isDateInClosedFiscalYear(parsedDate);
    if (isClosed && referenceType != 'fiscal_year_closing' && referenceType != 'opening_balance') {
      throw Exception('لا يمكن تسجيل أو تعديل قيود في سنة مالية مغلقة.');
    }

    final desc = description ?? 'قيد يدوي';
    final dId = int.tryParse(debitAccountId) ?? debitAccountId;
    final cId = int.tryParse(creditAccountId) ?? creditAccountId;

    final result = await _client.rpc('post_journal_entry', params: {
      'p_source_type': 'manual',
      'p_description': desc,
      'p_entry_date': dateStr,
      'p_company_id': null,
      'p_created_by': _client.auth.currentUser?.id,
      'p_source_id': referenceId,
      'p_lines': [
        {
          'account_id': dId,
          'debit': amount,
          'credit': 0,
          'currency': 'EGP',
          'description': desc,
        },
        {
          'account_id': cId,
          'debit': 0,
          'credit': amount,
          'currency': 'EGP',
          'description': desc,
        },
      ],
    });
    return result.toString();
  }

  /// Creates a balanced customer journal entry atomically via RPC.
  /// Returns the entry_number.
  Future<String> insertCustomerEntry({
    required String accountId,
    required String customerId,
    required double amount,
    required bool isDebit,
    String? description,
    String? transactionDate,
    Map<String, dynamic>? currencySnapshot,
  }) async {
    final result = await _client.rpc('create_customer_journal_entry', params: {
      'p_account_id': accountId,
      'p_customer_id': customerId,
      'p_amount': amount,
      'p_is_debit': isDebit,
      'p_description': description,
      'p_transaction_date': transactionDate,
      'p_currency_snapshot': currencySnapshot,
    });
    return result as String;
  }

  /// Creates a balanced supplier journal entry atomically via RPC.
  /// Returns the entry_number.
  Future<String> insertSupplierEntry({
    required String accountId,
    required String supplierCode,
    required double amount,
    required bool isDebit,
    String? description,
    String? transactionDate,
    Map<String, dynamic>? currencySnapshot,
  }) async {
    final result = await _client.rpc('create_supplier_journal_entry', params: {
      'p_account_id': accountId,
      'p_supplier_code': supplierCode,
      'p_amount': amount,
      'p_is_debit': isDebit,
      'p_description': description,
      'p_transaction_date': transactionDate,
      'p_currency_snapshot': currencySnapshot,
    });
    return result as String;
  }

  Future<List<TransactionModel>> getByAccountId(dynamic accountId) async {
    if (accountId == null) return [];
    return getByAccountIds([accountId.toString()]);
  }

  Future<List<TransactionModel>> getByAccountIds(List<String> accountIds) async {
    if (accountIds.isEmpty) return [];

    final List<TransactionModel> results = [];
    final Set<String> seenEntryKeys = {};

    // Support both integer and string IDs for Supabase / PostgREST queries
    final typedIds = accountIds.map((id) => int.tryParse(id) ?? id).toList();

    // Fetch accounts map for resolving account code and name safely
    final Map<String, Map<String, String>> accountInfoMap = {};
    try {
      final accData = await _client
          .from('accounts')
          .select('id, account_code, name, account_name')
          .inFilter('id', typedIds);
      for (final a in (accData as List)) {
        final m = Map<String, dynamic>.from(a as Map);
        final idStr = m['id']?.toString() ?? '';
        final code = (m['account_code'] ?? m['code'] ?? '').toString();
        final name = (m['account_name'] ?? m['name'] ?? '').toString();
        if (idStr.isNotEmpty) {
          accountInfoMap[idStr] = {'code': code, 'name': name};
        }
      }
    } catch (e) {
      debugPrint('TransactionDao: error fetching accounts info: $e');
    }

    // 1. Fetch from v_journal_entry_lines (Primary System Journal Entries & Lines)
    try {
      debugPrint('TransactionDao: querying v_journal_entry_lines with typedIds=$typedIds (accountIds=$accountIds)');
      final vData = await _client
          .from('v_journal_entry_lines')
          .select('*')
          .inFilter('account_id', typedIds)
          .order('transaction_date', ascending: true)
          .order('id', ascending: true);

      debugPrint('TransactionDao: v_journal_entry_lines returned ${(vData as List).length} rows');

      for (final raw in vData) {
        final row = Map<String, dynamic>.from(raw as Map);
        final accId = row['account_id']?.toString() ?? '';
        final accInfo = accountInfoMap[accId];

        final debit = (row['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (row['credit'] as num?)?.toDouble() ?? 0.0;
        final isDebit = debit > 0 || (debit == 0 && credit == 0);
        final amount = (row['amount'] as num?)?.toDouble() ?? (isDebit ? debit : credit);
        final type = (row['type']?.toString().isNotEmpty == true)
            ? row['type'].toString()
            : (isDebit ? 'debit' : 'credit');
        final currency = row['currency']?.toString() ?? 'EGP';

        final entryNumber = row['entry_number']?.toString() ?? row['id']?.toString() ?? '';
        final entryDate = row['transaction_date']?.toString() ?? row['created_at']?.toString() ?? '';
        final description = row['description']?.toString() ?? '';

        final tx = TransactionModel(
          id: 'vjel_${row['id']}',
          entryNumber: entryNumber,
          transactionDate: entryDate,
          type: type,
          amount: amount,
          accountId: accId,
          accountName: accInfo?['name'],
          accountCode: accInfo?['code'],
          description: description.isNotEmpty ? description : 'قيد يومية',
          createdAt: row['created_at']?.toString() ?? entryDate,
          currency: currency,
        );

        final key = '${tx.entryNumber}_${tx.accountId}_${tx.amount}_${tx.type}_${tx.currency}';
        if (!seenEntryKeys.contains(key)) {
          seenEntryKeys.add(key);
          results.add(tx);
        }
      }
    } catch (e) {
      debugPrint('TransactionDao.getByAccountIds (v_journal_entry_lines) error: $e');
    }

    // 2. Fetch from account_ledger_entries (GL Posting Engine & Opening Balances)
    try {
      debugPrint('TransactionDao: querying account_ledger_entries with typedIds=$typedIds');
      final ledgerData = await _client
          .from('account_ledger_entries')
          .select('''
            id,
            account_id,
            debit,
            credit,
            currency,
            description,
            created_at,
            journal_entries (
              id,
              entry_number,
              entry_date,
              description,
              source_type,
              source_id,
              status
            )
          ''')
          .inFilter('account_id', typedIds)
          .order('created_at', ascending: true);

      debugPrint('TransactionDao: account_ledger_entries returned ${(ledgerData as List).length} rows');
      for (final raw in (ledgerData as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final je = AppUtils.asMap(row['journal_entries']) ?? {};
        final accId = row['account_id']?.toString() ?? '';
        final accInfo = accountInfoMap[accId];

        final debit = (row['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (row['credit'] as num?)?.toDouble() ?? 0.0;
        final isDebit = debit > 0 || (debit == 0 && credit == 0);
        final amount = isDebit ? debit : credit;
        final type = isDebit ? 'debit' : 'credit';
        final ledgerCurrency = row['currency']?.toString() ?? 'EGP';

        final entryNumber = je['entry_number']?.toString() ?? row['id']?.toString() ?? '';
        final entryDate = je['entry_date']?.toString() ?? row['created_at']?.toString() ?? '';

        String description = row['description']?.toString() ?? '';
        if (description.isEmpty) {
          description = je['description']?.toString() ?? '';
        }
        if (description.isEmpty && je['source_type'] == 'opening_balance') {
          final code = accInfo?['code'] ?? '';
          if (code.startsWith('111')) {
            description = 'قيد الرصيد الافتتاحي للخزينة الرئيسية';
          } else if (code.startsWith('112')) {
            description = 'قيد الرصيد الافتتاحي للحساب البنكي';
          } else {
            description = 'قيد رصيد افتتاحي';
          }
        }

        final tx = TransactionModel(
          id: 'ale_${row['id']}',
          entryNumber: entryNumber,
          transactionDate: entryDate,
          type: type,
          amount: amount,
          accountId: accId,
          accountName: accInfo?['name'],
          accountCode: accInfo?['code'],
          description: description.isNotEmpty ? description : 'حركة محاسبية',
          createdAt: row['created_at']?.toString() ?? entryDate,
          currency: ledgerCurrency,
        );

        final key = '${tx.entryNumber}_${tx.accountId}_${tx.amount}_${tx.type}_${tx.currency}';
        if (!seenEntryKeys.contains(key)) {
          seenEntryKeys.add(key);
          results.add(tx);
        }
      }
    } catch (e) {
      debugPrint('TransactionDao.getByAccountIds (ledger) error: $e');
    }

    // 3. Fetch from legacy transactions table
    try {
      debugPrint('TransactionDao: querying legacy transactions with typedIds=$typedIds');
      final txData = await _client
          .from('transactions')
          .select(_selectWithEmbeds)
          .inFilter('account_id', typedIds)
          .order('transaction_date', ascending: true)
          .order('id', ascending: true);

      debugPrint('TransactionDao: legacy transactions returned ${(txData as List).length} rows');
      final legacyTransactions = (txData as List).map(_flattenRow).toList();
      for (final legacyTx in legacyTransactions) {
        final key = '${legacyTx.entryNumber}_${legacyTx.accountId}_${legacyTx.amount}_${legacyTx.type}';
        if (!seenEntryKeys.contains(key)) {
          seenEntryKeys.add(key);
          results.add(legacyTx);
        }
      }
    } catch (e) {
      debugPrint('TransactionDao.getByAccountIds (legacy) error: $e');
    }

    // 3. Sort chronologically
    results.sort((a, b) {
      final cmp = a.transactionDate.compareTo(b.transactionDate);
      if (cmp != 0) return cmp;
      return (a.id ?? '').compareTo(b.id ?? '');
    });

    debugPrint('TransactionDao: total results=${results.length}');
    return results;
  }

  Future<List<TransactionModel>> getByInvoice(int invoiceId) async {
    final data = await _client
        .from('transactions')
        .select(_selectWithEmbeds)
        .eq('reference_type', 'invoice')
        .eq('reference_id', invoiceId.toString())
        .order('transaction_date', ascending: true)
        .order('id', ascending: true);
    await _preloadAccounts(data);
    return data.map(_flattenRow).toList();
  }

  Future<List<TransactionModel>> getByPurchase(int purchaseId) async {
    final data = await _client
        .from('transactions')
        .select(_selectWithEmbeds)
        .eq('reference_type', 'purchase')
        .eq('reference_id', purchaseId.toString())
        .order('transaction_date', ascending: true)
        .order('id', ascending: true);
    await _preloadAccounts(data);
    return data.map(_flattenRow).toList();
  }

  Future<void> delete(int id) async {
    await _client.from('transactions').delete().eq('id', id.toString());
  }

  Future<double> getBalanceBeforeDate({
    required String date,
  }) async {
    final data = await _client
        .from('transactions')
        .select('debit, credit')
        .lt('transaction_date', date);

    double balance = 0.0;
    for (final row in data) {
      final debit = (row['debit'] as num).toDouble();
      final credit = (row['credit'] as num).toDouble();
      balance += debit - credit;
    }
    return balance;
  }
}
