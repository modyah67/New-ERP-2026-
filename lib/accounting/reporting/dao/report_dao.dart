/// ReportDao — READ-ONLY data access layer for accounting reports
///
/// This DAO never modifies data. It only queries the existing tables
/// using Supabase client. All queries are read-only.
///
/// Handles the dual debit/credit representation:
/// - SQL-written rows: `debit`/`credit` columns populated
/// - Dart-written rows: `type`/`amount` columns populated
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils.dart';
import '../../../data/models/account_model.dart';
import '../models/report_models.dart';
import '../utils/account_classifier.dart';

class ReportDao {
  final _client = Supabase.instance.client;

  // ─────────────────────────────────────────────
  // ACCOUNTS CACHE (60-second TTL)
  // ─────────────────────────────────────────────

  List<AccountHierarchy>? _cachedAccounts;
  DateTime? _accountsCacheTime;
  static const _cacheTtl = Duration(seconds: 60);

  /// Invalidate the accounts cache (call after chart of accounts changes)
  void invalidateAccountsCache() {
    _cachedAccounts = null;
    _accountsCacheTime = null;
  }

  // ─────────────────────────────────────────────
  // ACCOUNT HIERARCHY
  // ─────────────────────────────────────────────

  /// Fetch all active accounts and build hierarchy
  Future<List<AccountHierarchy>> getAccountHierarchy() async {
    final accounts = await getAllAccounts();
    return _buildTree(accounts);
  }

  /// Build parent-child tree from flat list
  List<AccountHierarchy> _buildTree(List<AccountHierarchy> flat) {
    final parentToChildrenMap = <String, List<AccountHierarchy>>{};
    final flatMap = <String, AccountHierarchy>{};
    for (final a in flat) {
      flatMap[a.id] = a;
      if (a.parentId != null && a.parentId!.isNotEmpty) {
        parentToChildrenMap.putIfAbsent(a.parentId!, () => []).add(a);
      }
    }

    AccountHierarchy buildSubtree(AccountHierarchy node) {
      final children = parentToChildrenMap[node.id] ?? [];
      final resolvedChildren = children.map(buildSubtree).toList();
      return node.copyWith(children: resolvedChildren);
    }

    final roots = flat
        .where((a) =>
            a.parentId == null ||
            a.parentId!.isEmpty ||
            !flatMap.containsKey(a.parentId))
        .map(buildSubtree)
        .toList();

    return roots;
  }

  // ─────────────────────────────────────────────
  // ACCOUNT LIST (with 60s in-memory cache)
  // ─────────────────────────────────────────────

  /// Get all active accounts as flat list
  ///
  /// Results are cached in memory for 60 seconds to avoid redundant
  /// queries within the same report generation session.
  Future<List<AccountHierarchy>> getAllAccounts() async {
    if (_cachedAccounts != null && _accountsCacheTime != null) {
      if (DateTime.now().difference(_accountsCacheTime!) < _cacheTtl) {
        return _cachedAccounts!;
      }
    }

    final data = await _client
        .from('accounts')
        .select(
            'id, account_code, name, account_name, account_type, parent_id, is_active')
        .eq('is_active', true)
        .order('account_code', ascending: true);

    final accounts = (data as List).map((row) {
      final rowMap = Map<String, dynamic>.from(row as Map);
      final classification = AccountClassifier.classify(
        rowMap['account_type']?.toString() ?? '',
      );
      final model = AccountModel.fromMap(rowMap);
      return AccountHierarchy(
        id: rowMap['id'].toString(),
        code: model.code,
        name: model.name,
        nameAr: model.displayName,
        classification: classification,
        parentId: rowMap['parent_id']?.toString(),
      );
    }).toList();

    _cachedAccounts = accounts;
    _accountsCacheTime = DateTime.now();
    return accounts;
  }

  // ─────────────────────────────────────────────
  // TRANSACTIONS (GL Journal)
  // ─────────────────────────────────────────────

  /// Fetch transactions from the `transactions` table
  ///
  /// Returns raw rows with both debit/credit and type/amount patterns.
  /// Caller should use [BalanceCalculator.normalizeRow] to extract values.
  Future<List<Map<String, dynamic>>> getTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    String? accountId,
    String? accountType,
    String? entityType,
    String? entityId,
    int? limit,
    int? offset,
  }) async {
    var query = _client.from('account_ledger_entries').select('''
      id, account_id, debit, credit, description, created_at,
      journal_entries!inner(id, entry_number, entry_date, description, source_type, source_id)
    ''');

    if (fromDate != null) {
      final fromStr = AppUtils.formatDateForDb(fromDate);
      query = query.gte('journal_entries.entry_date', fromStr);
    }
    if (toDate != null) {
      final toStr = AppUtils.formatDateForDb(toDate);
      query = query.lte('journal_entries.entry_date', toStr);
    }
    if (accountId != null) {
      query = query.eq('account_id', accountId);
    }

    final data = await query
        .order('id', ascending: true);

    // Collect unique account_ids and fetch account info separately
    final accountIds = <String>{};
    for (final row in (data as List)) {
      final m = row as Map<String, dynamic>;
      if (m['account_id'] != null) accountIds.add(m['account_id'].toString());
    }
    final Map<String, Map<String, dynamic>> accountsMap = {};
    if (accountIds.isNotEmpty) {
      try {
        final accData = await _client
            .from('accounts')
            .select('id, name, account_code, account_type')
            .inFilter('id', accountIds.toList());
        for (final a in (accData as List)) {
          final m = Map<String, dynamic>.from(a as Map);
          accountsMap[m['id'].toString()] = m;
        }
      } catch (_) {}
    }

    // Flatten embedded journal entry and account data
    return (data as List).map((row) {
      final flat = Map<String, dynamic>.from(row as Map);
      final je = AppUtils.asMap(flat.remove('journal_entries'));
      flat.remove('accounts');
      final accId = flat['account_id']?.toString();
      final account = accId != null ? accountsMap[accId] : null;
      if (je != null) {
        flat['transaction_date'] = je['entry_date'];
        flat['entry_number'] = je['entry_number'];
        flat['reference_type'] = je['source_type'];
        flat['reference_id'] = je['source_id'];
        flat['description'] = flat['description'] ?? je['description'];
      }
      if (account != null) {
        flat['account_name'] = account['name'];
        flat['account_code'] = account['account_code'];
        flat['account_type'] = account['account_type'];
      }
      return flat;
    }).toList();
  }

  /// Fetch transactions before a date (for opening balance computation)
  ///
  /// **DEPRECATED**: Use [getBalanceBeforeDate] instead for better performance.
  /// This method downloads all raw rows. The replacement uses a server-side RPC.
  @Deprecated(
      'Use getBalanceBeforeDate() instead — returns aggregated sums via RPC')
  Future<List<Map<String, dynamic>>> getTransactionsBefore({
    required DateTime beforeDate,
    String? accountId,
  }) async {
    var query = _client.from('account_ledger_entries').select('''
      account_id, debit, credit,
      journal_entries!inner(entry_date)
    ''');

    final beforeStr = AppUtils.formatDateForDb(beforeDate);
    query = query.lt('journal_entries.entry_date', beforeStr);

    if (accountId != null) {
      query = query.eq('account_id', accountId);
    }

    final data = await query;
    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ─────────────────────────────────────────────
  // SERVER-SIDE AGGREGATED BALANCE QUERIES (RPCs)
  // ─────────────────────────────────────────────

  /// Get debit/credit totals per account for a date range
  ///
  /// Uses server-side PostgreSQL GROUP BY via RPC.
  /// Falls back to client-side aggregation if RPC is unavailable.
  ///
  /// When [currency] is null (default): sums amount_in_base_currency
  /// to produce consistent EGP-equivalent totals across all currencies.
  /// When [currency] is provided: filters to that currency and sums
  /// raw debit/credit in that currency's original amounts.
  Future<List<Map<String, dynamic>>> getAccountTotals({
    DateTime? fromDate,
    DateTime? toDate,
    String? currency,
    bool excludeClosing = false,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (fromDate != null) {
        params['p_from'] = AppUtils.formatDateForDb(fromDate);
      }
      if (toDate != null) params['p_to'] = AppUtils.formatDateForDb(toDate);
      if (currency != null && currency.isNotEmpty) {
        params['p_currency'] = currency;
      }
      if (excludeClosing) {
        params['p_exclude_closing'] = true;
      }

      final data = await _client.rpc('get_account_totals_rpc', params: params);
      final results = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return results;
    } catch (e) {
      // Fallback: client-side aggregation if RPC not deployed yet
      return _getAccountTotalsFallback(
        fromDate: fromDate,
        toDate: toDate,
        currency: currency,
        excludeClosing: excludeClosing,
      );
    }
  }

  /// Client-side fallback for getAccountTotals (pre-RPC behavior)
  ///
  /// When [currency] is null: uses amount_in_base_currency for
  /// consistent EGP-equivalent totals across all currencies.
  /// When [currency] is provided: filters to that currency and sums
  /// raw debit/credit in that currency.
  Future<List<Map<String, dynamic>>> _getAccountTotalsFallback({
    DateTime? fromDate,
    DateTime? toDate,
    String? currency,
    bool excludeClosing = false,
  }) async {
    var query = _client.from('account_ledger_entries').select('''
      account_id, debit, credit, currency, amount_in_base_currency,
      journal_entries!inner(entry_date, source_type)
    ''');

    if (excludeClosing) {
      query = query.neq('journal_entries.source_type', 'fiscal_year_closing');
    }

    if (fromDate != null) {
      query = query.gte('journal_entries.entry_date', AppUtils.formatDateForDb(fromDate));
    }
    if (toDate != null) {
      query = query.lte('journal_entries.entry_date', AppUtils.formatDateForDb(toDate));
    }
    if (currency != null && currency.isNotEmpty) {
      query = query.eq('currency', currency);
    }

    final data = await query;

    final totals = <String, Map<String, double>>{};
    for (final row in data as List) {
      final accountId = row['account_id']?.toString() ?? '';
      if (accountId.isEmpty) continue;

      double debitAmount;
      double creditAmount;

      if (currency == null || currency.isEmpty) {
        // DEFAULT: use amount_in_base_currency (EGP-equivalent)
        final baseAmount = (row['amount_in_base_currency'] as num?)?.toDouble() ?? 0.0;
        final rawDebit = (row['debit'] as num?)?.toDouble() ?? 0.0;
        final rawCredit = (row['credit'] as num?)?.toDouble() ?? 0.0;
        debitAmount = rawDebit > 0 ? baseAmount : 0.0;
        creditAmount = rawCredit > 0 ? baseAmount : 0.0;
      } else {
        // SPECIFIC CURRENCY: use raw debit/credit
        debitAmount = (row['debit'] as num?)?.toDouble() ?? 0.0;
        creditAmount = (row['credit'] as num?)?.toDouble() ?? 0.0;
      }

      totals.putIfAbsent(accountId, () => {'debit': 0.0, 'credit': 0.0});
      totals[accountId]!['debit'] = totals[accountId]!['debit']! + debitAmount;
      totals[accountId]!['credit'] = totals[accountId]!['credit']! + creditAmount;
    }

    return totals.entries
        .map((e) => {
              'account_id': e.key,
              'debit': e.value['debit'],
              'credit': e.value['credit'],
            })
        .toList();
  }


  /// Get total debit and credit for a specific account in a date range
  ///
  /// Uses server-side aggregation via RPC.
  Future<({double debit, double credit})> getAccountTotal({
    required String accountId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_account_id': accountId,
      };
      if (fromDate != null)
        params['p_from'] = AppUtils.formatDateForDb(fromDate);
      if (toDate != null) params['p_to'] = AppUtils.formatDateForDb(toDate);

      final data =
          await _client.rpc('get_account_total_by_id_rpc', params: params);
      final row = (data as List).isNotEmpty ? data.first : null;
      return (
        debit: (row?['debit'] as num?)?.toDouble() ?? 0.0,
        credit: (row?['credit'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      // Fallback: client-side aggregation
      return _getAccountTotalFallback(
        accountId: accountId,
        fromDate: fromDate,
        toDate: toDate,
      );
    }
  }

  /// Client-side fallback for getAccountTotal
  Future<({double debit, double credit})> _getAccountTotalFallback({
    required String accountId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var query =
        _client.from('transactions').select('debit, credit, amount, transaction_date');

    query = query.eq('account_id', accountId);
    if (fromDate != null) {
      query = query.gte('transaction_date', AppUtils.formatDateForDb(fromDate));
    }
    if (toDate != null) {
      query = query.lte('transaction_date', AppUtils.formatDateForDb(toDate));
    }

    final data = await query;
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final row in data as List) {
      final rawDebit = (row['debit'] as num?)?.toDouble() ?? 0.0;
      final rawCredit = (row['credit'] as num?)?.toDouble() ?? 0.0;

      totalDebit += rawDebit;
      totalCredit += rawCredit;
    }

    return (debit: totalDebit, credit: totalCredit);
  }

  /// Fetch opening balance before a given date
  ///
  /// Uses server-side SQL function `get_balance_before_date_rpc`
  /// directly — no raw row download needed.
  Future<({double debit, double credit})> getBalanceBeforeDate({
    required String accountId,
    required DateTime beforeDate,
    String? currency,
  }) async {
    accountId = (await _resolveAccountId(accountId)) ?? accountId;
    try {
      final params = <String, dynamic>{
        'p_account_id': accountId.isNotEmpty ? accountId : null,
        'p_before_date': AppUtils.formatDateForDb(beforeDate),
        'p_currency': (currency != null && currency.isNotEmpty && currency != 'ALL' && currency != 'الكل') ? currency : null,
      };
      final data = await _client.rpc('get_balance_before_date_rpc', params: params);
      final row = (data as List).isNotEmpty ? data.first : null;
      return (
        debit: (row?['debit'] as num?)?.toDouble() ?? 0.0,
        credit: (row?['credit'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      return _getBalanceBeforeDateFallback(
        accountId: accountId,
        beforeDate: beforeDate,
        currency: currency,
      );
    }
  }

  /// Client-side fallback for getBalanceBeforeDate
  Future<({double debit, double credit})> _getBalanceBeforeDateFallback({
    required String accountId,
    required DateTime beforeDate,
    String? currency,
  }) async {
    accountId = (await _resolveAccountId(accountId)) ?? accountId;
    var query = _client
        .from('v_journal_entry_lines')
        .select('debit, credit, amount_in_base_currency')
        .lt('transaction_date', AppUtils.formatDateForDb(beforeDate));

    if (accountId.isNotEmpty) {
      query = query.or('account_id.eq.$accountId,account_code.eq.$accountId');
    }

    if (currency != null && currency.isNotEmpty && currency != 'ALL' && currency != 'الكل') {
      query = query.eq('currency', currency);
    }
    
    final data = await query;

    final isBase = currency == null || currency.isEmpty || currency == 'ALL' || currency == 'الكل' || currency == 'EGP';
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final row in data as List) {
      final rawDebit = (row['debit'] as num?)?.toDouble() ?? 0.0;
      final rawCredit = (row['credit'] as num?)?.toDouble() ?? 0.0;
      final baseAmount = (row['amount_in_base_currency'] as num?)?.toDouble() ?? (rawDebit > 0 ? rawDebit : rawCredit);

      if (isBase) {
        if (rawDebit > 0) totalDebit += baseAmount;
        if (rawCredit > 0) totalCredit += baseAmount;
      } else {
        totalDebit += rawDebit;
        totalCredit += rawCredit;
      }
    }

    return (debit: totalDebit, credit: totalCredit);
  }

  /// Client-side fallback for cursor-based pagination
  Future<
      ({
        List<Map<String, dynamic>> rows,
        String? nextCursor,
        bool hasMore,
        double openingDebit,
        double openingCredit,
      })> _getLedgerPageFallback({
    String? accountId,
    DateTime? fromDate,
    DateTime? toDate,
    String? cursor,
    int limit = 50,
    String? currency,
  }) async {
    accountId = (await _resolveAccountId(accountId)) ?? accountId;
    var query = _client.from('v_journal_entry_lines').select('*');

    if (fromDate != null) {
      query = query.gte('transaction_date', AppUtils.formatDateForDb(fromDate));
    }
    if (toDate != null) {
      query = query.lte('transaction_date', AppUtils.formatDateForDb(toDate));
    }
    if (accountId != null && accountId.isNotEmpty) {
      query = query.or('account_id.eq.$accountId,account_code.eq.$accountId');
    }
    if (currency != null && currency.isNotEmpty && currency != 'ALL' && currency != 'الكل') {
      query = query.eq('currency', currency);
    }

    final data = await query
        .order('transaction_date', ascending: true)
        .order('id', ascending: true)
        .limit(limit + 1);

    // Collect unique account_ids and fetch account info separately
    final accountIds = <String>{};
    for (final row in (data as List)) {
      final m = row as Map<String, dynamic>;
      if (m['account_id'] != null) accountIds.add(m['account_id'].toString());
    }
    final Map<String, Map<String, dynamic>> accountsMap = {};
    if (accountIds.isNotEmpty) {
      try {
        final accData = await _client
            .from('accounts')
            .select('id, name, account_name, account_code, account_type')
            .inFilter('id', accountIds.toList());
        for (final a in (accData as List)) {
          final m = Map<String, dynamic>.from(a as Map);
          accountsMap[m['id'].toString()] = m;
        }
      } catch (_) {}
    }

    final isBase = currency == null || currency.isEmpty || currency == 'ALL' || currency == 'الكل' || currency == 'EGP';

    final list = (data as List).map((row) {
      final flat = Map<String, dynamic>.from(row as Map);
      final accId = flat['account_id']?.toString();
      final account = accId != null ? accountsMap[accId] : null;
      final accountModel = AccountModel.fromMap(account ?? {});

      final acCode = flat['account_code']?.toString();
      final acName = flat['account_name']?.toString();

      final rawDebit = (flat['debit'] as num?)?.toDouble() ?? 0.0;
      final rawCredit = (flat['credit'] as num?)?.toDouble() ?? 0.0;
      final baseAmount = (flat['amount_in_base_currency'] as num?)?.toDouble() ?? (rawDebit > 0 ? rawDebit : rawCredit);

      final debit = isBase ? (rawDebit > 0 ? baseAmount : 0.0) : rawDebit;
      final credit = isBase ? (rawCredit > 0 ? baseAmount : 0.0) : rawCredit;

      return {
        'id': flat['id']?.toString(),
        'date': flat['transaction_date']?.toString() ?? '',
        'entry_number': flat['entry_number']?.toString() ?? '',
        'account_id': flat['account_id']?.toString(),
        'account_code': (acCode != null && acCode.isNotEmpty) ? acCode : accountModel.code,
        'account_name': (acName != null && acName.isNotEmpty) ? acName : accountModel.displayName,
        'description': flat['description']?.toString() ?? '',
        'debit': debit,
        'credit': credit,
        'reference_type': flat['source_type']?.toString() ?? '',
        'reference_id': flat['source_id']?.toString() ?? '',
      };
    }).toList();

    final hasMore = list.length > limit;
    final pageRows = hasMore ? list.sublist(0, limit) : list;

    // Compute cursor from last row
    String? nextCursor;
    if (hasMore && pageRows.isNotEmpty) {
      final last = pageRows.last;
      final lastDate = last['date']?.toString() ?? '';
      final lastId = last['id']?.toString() ?? '';
      nextCursor = '$lastDate|$lastId';
    }

    // Compute opening balance before cursor
    double obDebit = 0;
    double obCredit = 0;
    if (!hasMore) {
      if (fromDate != null) {
        final obResult = await getBalanceBeforeDate(
          accountId: accountId ?? '',
          beforeDate: fromDate,
          currency: currency,
        );
        obDebit = obResult.debit;
        obCredit = obResult.credit;
      }
    }

    return (
      rows: pageRows,
      nextCursor: nextCursor,
      hasMore: hasMore,
      openingDebit: obDebit,
      openingCredit: obCredit
    );
  }

  // ─────────────────────────────────────────────
  // ENTITY LEDGER (ledger_entries table)
  // ─────────────────────────────────────────────

  /// Fetch ledger entries for an entity (customer/supplier/etc.)
  Future<List<Map<String, dynamic>>> getEntityLedger({
    required String entityType,
    required String entityId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var query = _client
        .from('ledger_entries')
        .select(
          'id, entry_type, amount, created_at, description, reference_type, reference_id, currency',
        )
        .eq(
          'entity_type',
          entityType,
        )
        .eq('entity_id', entityId);

    if (fromDate != null) {
      query = query.gte('created_at', fromDate.toIso8601String());
    }
    if (toDate != null) {
      query = query.lte(
          'created_at', toDate.add(const Duration(days: 1)).toIso8601String());
    }

    final data = await query.order('created_at', ascending: true);
    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ─────────────────────────────────────────────
  // CURRENCY / EXCHANGE RATES
  // ─────────────────────────────────────────────

  /// Get latest exchange rates (currency → EGP rate)
  ///
  /// Uses server-side DISTINCT ON via RPC.
  Future<Map<String, double>> getExchangeRates() async {
    try {
      final data = await _client.rpc('get_latest_exchange_rates_rpc');

      final rates = <String, double>{};
      for (final row in data as List) {
        final currency = row['currency_code'] as String;
        final rate = (row['rate'] as num?)?.toDouble() ?? 1.0;
        rates[currency] = rate;
      }

      // Ensure EGP is always 1.0
      rates['EGP'] = 1.0;
      return rates;
    } catch (e) {
      // Fallback: client-side query if RPC not deployed yet
      return _getExchangeRatesFallback();
    }
  }

  /// Client-side fallback for getExchangeRates
  Future<Map<String, double>> _getExchangeRatesFallback() async {
    try {
      final data = await _client
          .from('exchange_rates')
          .select('currency_code, rate_to_egp')
          .order('updated_at', ascending: false);

      final rates = <String, double>{};
      for (final row in data as List) {
        final currency = row['currency_code'] as String;
        final rate = (row['rate_to_egp'] as num?)?.toDouble() ?? 1.0;
        if (!rates.containsKey(currency)) {
          rates[currency] = rate;
        }
      }

      // Ensure EGP is always 1.0
      rates['EGP'] = 1.0;
      return rates;
    } catch (e) {
      // Last resort: hardcoded fallback (log warning)
      return {'EGP': 1.0, 'USD': 50.0, 'EUR': 55.0, 'GBP': 63.0};
    }
  }

  // ─────────────────────────────────────────────
  // TREASURY TRANSACTIONS (for Cash Flow)
  // ─────────────────────────────────────────────

  /// Fetch treasury transactions for cash flow reporting
  Future<List<Map<String, dynamic>>> getTreasuryTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    String? currency,
  }) async {
    var query = _client.from('treasury_transactions').select('''
      id, treasury_id, type, currency, amount, description,
      customer_id, supplier_id, shareholder_id, reference_type, created_at
    ''').neq('status', 'draft');

    if (fromDate != null) {
      query = query.gte('created_at', fromDate.toIso8601String());
    }
    if (toDate != null) {
      query = query.lte(
          'created_at', toDate.add(const Duration(days: 1)).toIso8601String());
    }
    if (currency != null) {
      query = query.eq('currency', currency);
    }

    final data = await query.order('created_at', ascending: true);
    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ─────────────────────────────────────────────
  // BANK ACCOUNT TRANSACTIONS (for Cash Flow)
  // ─────────────────────────────────────────────

  /// Fetch bank account transactions for cash flow reporting
  Future<List<Map<String, dynamic>>> getBankTransactions({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var query = _client.from('bank_account_transactions').select('''
      id, bank_account_id, type, amount, description, created_at, entity_type,
      bank_accounts(name, currency)
    ''').neq('status', 'draft');

    if (fromDate != null) {
      query = query.gte('created_at', fromDate.toIso8601String());
    }
    if (toDate != null) {
      query = query.lte(
          'created_at', toDate.add(const Duration(days: 1)).toIso8601String());
    }

    final data = await query.order('created_at', ascending: true);
    return (data as List).map((row) {
      final flat = Map<String, dynamic>.from(row as Map);
      final bank = AppUtils.asMap(flat.remove('bank_accounts'));
      if (bank != null) {
        flat['bank_name'] = bank['name'];
        flat['bank_currency'] = bank['currency'];
      }
      return flat;
    }).toList();
  }

  // ─────────────────────────────────────────────
  // ACCOUNT BALANCE (denormalized)
  // ─────────────────────────────────────────────

  /// Read the denormalized balance from accounts table
  ///
  /// NOTE: This reads the STORED balance, not computed from transactions.
  /// Use with caution — may drift from actual transaction totals.
  Future<Map<String, double>> getStoredAccountBalances() async {
    final data = await _client
        .from('accounts')
        .select('id, balance')
        .eq('is_active', true);

    final balances = <String, double>{};
    for (final row in data as List) {
      final id = row['id'].toString();
      final balance = (row['balance'] as num?)?.toDouble() ?? 0.0;
      balances[id] = balance;
    }
    return balances;
  }

  /// Get account balance by code
  Future<double?> getAccountBalanceByCode(String accountCode) async {
    final data = await _client
        .from('accounts')
        .select('balance')
        .eq('account_code', accountCode)
        .maybeSingle();

    if (data == null) return null;
    return (data['balance'] as num?)?.toDouble();
  }

  // ─────────────────────────────────────────────
  // CURSOR-BASED PAGINATION (GL)
  // ─────────────────────────────────────────────

  /// Fetch a single page of transactions with cursor-based pagination.
  ///
  /// Returns: (rows, nextCursor, hasMore, openingBalance)
  Future<
      ({
        List<Map<String, dynamic>> rows,
        String? nextCursor,
        bool hasMore,
        double openingDebit,
        double openingCredit,
      })> getLedgerPage({
    String? accountId,
    DateTime? fromDate,
    DateTime? toDate,
    String? cursor,
    int limit = 50,
    String? currency,
  }) async {
    accountId = (await _resolveAccountId(accountId)) ?? accountId;
    try {
      final params = <String, dynamic>{
        'p_limit': limit,
      };
      if (accountId != null && accountId.isNotEmpty) {
        params['p_account_id'] = accountId;
      }
      if (fromDate != null) {
        params['p_from_date'] = AppUtils.formatDateForDb(fromDate);
      }
      if (toDate != null) {
        params['p_to_date'] = AppUtils.formatDateForDb(toDate);
      }
      if (cursor != null) {
        final parts = cursor.split('|');
        if (parts.length == 2) {
          params['p_cursor_date'] = parts[0];
          params['p_cursor_id'] = parts[1];
        }
      }
      if (currency != null && currency.isNotEmpty && currency != 'ALL' && currency != 'الكل') {
        params['p_currency'] = currency;
      }

      final data = await _client.rpc('get_ledger_page_rpc', params: params);
      final list = data as List? ?? [];

      if (list.isEmpty) {
        double obDebit = 0.0;
        double obCredit = 0.0;
        if (fromDate != null) {
          final obResult = await getBalanceBeforeDate(
            accountId: accountId ?? '',
            beforeDate: fromDate,
            currency: currency,
          );
          obDebit = obResult.debit;
          obCredit = obResult.credit;
        }
        return (
          rows: <Map<String, dynamic>>[],
          nextCursor: null,
          hasMore: false,
          openingDebit: obDebit,
          openingCredit: obCredit,
        );
      }

      final last = list.last;
      final hasMore = last['has_more'] == true;
      final nextCursorDate = last['next_cursor_date']?.toString();
      final nextCursorId = last['next_cursor_id']?.toString();
      final nextCursor =
          hasMore && nextCursorDate != null && nextCursorId != null
              ? '$nextCursorDate|$nextCursorId'
              : null;

      final obDebit =
          (last['opening_balance_debit'] as num?)?.toDouble() ?? 0.0;
      final obCredit =
          (last['opening_balance_credit'] as num?)?.toDouble() ?? 0.0;

      final rows = list.map((row) {
        final flat = Map<String, dynamic>.from(row as Map);
        flat.remove('next_cursor_date');
        flat.remove('next_cursor_id');
        flat.remove('has_more');
        flat.remove('opening_balance_debit');
        flat.remove('opening_balance_credit');
        return flat;
      }).toList();

      return (
        rows: rows,
        nextCursor: nextCursor,
        hasMore: hasMore,
        openingDebit: obDebit,
        openingCredit: obCredit
      );
    } catch (e) {
      // Fallback: client-side cursor pagination
      return _getLedgerPageFallback(
        accountId: accountId,
        fromDate: fromDate,
        toDate: toDate,
        cursor: cursor,
        limit: limit,
        currency: currency,
      );
    }
  }



  Future<String?> _resolveAccountId(String? codeOrId) async {
    if (codeOrId == null || codeOrId.isEmpty) return null;
    final accounts = await getAllAccounts();
    final byCode = accounts.where((a) => a.code == codeOrId).firstOrNull;
    if (byCode != null) return byCode.code;
    final byId = accounts.where((a) => a.id == codeOrId).firstOrNull;
    if (byId != null) return byId.code;
    return codeOrId;
  }
}