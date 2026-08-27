// AccountLedgerService — Unified accounting engine for any account's ledger
//
// This service provides a single entry point to fetch ledger entries for
// ANY account in the Chart of Accounts. It uses the same data source
// (ReportDao / account_ledger_entries + journal_entries) as the General Ledger,
// ensuring consistency across all screens.
//
// Key design decisions:
// - No entity-type-specific logic (no "if supplier", "if customer", etc.)
// - Account nature determined from AccountClassifier (not from entity type)
// - Opening balance computed server-side via RPC
// - Deterministic ordering: entry_date ASC → created_at ASC → id ASC
// - Single data source: account_ledger_entries joined with journal_entries
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../accounting/reporting/dao/report_dao.dart';
import '../../accounting/reporting/utils/account_classifier.dart';
import '../../core/utils.dart';
import '../models/account_ledger_result.dart';
import '../models/account_model.dart';

class AccountLedgerService {
  final ReportDao _reportDao = ReportDao();
  final _client = Supabase.instance.client;

  /// Fetches the complete ledger for an account (or a set of accounts).
  ///
  /// [accountIds] - One or more account IDs to fetch entries for.
  ///   For a leaf account, pass a single ID.
  ///   For a branch account, pass all descendant IDs.
  /// [accountType] - The account type string (asset, liability, equity, revenue, expense).
  /// [fromDate] / [toDate] - Optional date range filter.
  /// [currency] - Optional currency filter.
  ///
  /// Returns an [AccountLedgerResult] with pre-computed opening balance,
  /// running balances, totals, and deterministically sorted entries.
  Future<AccountLedgerResult> getAccountLedger({
    required List<String> accountIds,
    required String accountType,
    DateTime? fromDate,
    DateTime? toDate,
    String? currency,
  }) async {
    if (accountIds.isEmpty) return AccountLedgerResult.empty;

    final classification = AccountClassifier.classify(accountType);
    final isCreditNormal = classification.isCreditNormal;

    // ── 1. Fetch opening balance (sum of debit/credit before fromDate) ──
    double obDebit = 0.0;
    double obCredit = 0.0;

    if (fromDate != null) {
      for (final accId in accountIds) {
        try {
          final ob = await _reportDao.getBalanceBeforeDate(
            accountId: accId,
            beforeDate: fromDate,
            currency: currency,
          );
          obDebit += ob.debit;
          obCredit += ob.credit;
        } catch (e) {
          debugPrint('AccountLedgerService: getBalanceBeforeDate error for $accId: $e');
        }
      }
    }

    final openingBalance = isCreditNormal
        ? obCredit - obDebit
        : obDebit - obCredit;

    // ── 2. Fetch all entries within the period ──
    final rawEntries = <Map<String, dynamic>>[];

    for (final accId in accountIds) {
      try {
        final entries = await _fetchLedgerEntries(
          accountId: accId,
          fromDate: fromDate,
          toDate: toDate,
          currency: currency,
        );
        rawEntries.addAll(entries);
      } catch (e) {
        debugPrint('AccountLedgerService: fetch entries error for $accId: $e');
      }
    }

    // ── 3. Sort deterministically ──
    // Primary: entry_date ASC
    // Secondary: created_at ASC
    // Tertiary: id ASC (tie-breaker)
    rawEntries.sort((a, b) {
      final dateA = a['date']?.toString() ?? '';
      final dateB = b['date']?.toString() ?? '';
      final dateCmp = dateA.compareTo(dateB);
      if (dateCmp != 0) return dateCmp;

      final createdA = a['created_at']?.toString() ?? '';
      final createdB = b['created_at']?.toString() ?? '';
      final createdCmp = createdA.compareTo(createdB);
      if (createdCmp != 0) return createdCmp;

      final idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
      final idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
      return idA.compareTo(idB);
    });

    // ── 4. Compute running balance and totals ──
    final isBaseMode = (currency == null || currency.isEmpty || currency == 'ALL' || currency == 'الكل' || currency == 'EGP' || currency == 'ج.م');

    double runningBalance = openingBalance;
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    final entries = <AccountLedgerEntry>[];

    for (final raw in rawEntries) {
      double debit = (raw['debit'] as num?)?.toDouble() ?? 0.0;
      double credit = (raw['credit'] as num?)?.toDouble() ?? 0.0;

      if (isBaseMode) {
        final baseAmount = (raw['amount_in_base_currency'] as num?)?.toDouble() ?? (debit > 0 ? debit : credit);
        if (debit > 0) debit = baseAmount;
        if (credit > 0) credit = baseAmount;
      }

      totalDebit += debit;
      totalCredit += credit;

      // Running balance respects account nature
      if (isCreditNormal) {
        runningBalance += credit - debit;
      } else {
        runningBalance += debit - credit;
      }

      final dateStr = raw['date']?.toString() ?? '';
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();

      entries.add(AccountLedgerEntry(
        id: raw['id']?.toString() ?? '',
        date: date,
        entryNumber: raw['entry_number']?.toString(),
        referenceType: raw['reference_type']?.toString(),
        referenceId: raw['reference_id']?.toString(),
        description: _buildDescription(raw),
        debit: debit,
        credit: credit,
        runningBalance: runningBalance,
        currency: isBaseMode ? 'ج.م' : (raw['currency']?.toString() ?? currency),
        accountCode: raw['account_code']?.toString() ?? '',
        accountName: raw['account_name']?.toString() ?? '',
        createdAt: raw['created_at']?.toString() ?? '',
      ));
    }

    final closingBalance = runningBalance;

    return AccountLedgerResult(
      openingBalance: openingBalance,
      closingBalance: closingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      transactionCount: entries.length,
      currency: isBaseMode ? 'ج.م' : currency,
      isCreditNormal: isCreditNormal,
      accountType: accountType,
      entries: entries,
    );
  }

  /// Fetches ledger entries for a single account from account_ledger_entries
  /// joined with journal_entries — the same source used by General Ledger.
  Future<List<Map<String, dynamic>>> _fetchLedgerEntries({
    required String accountId,
    DateTime? fromDate,
    DateTime? toDate,
    String? currency,
  }) async {
    // Use v_journal_entry_lines view which joins account_ledger_entries + journal_entries + accounts
    var query = _client.from('v_journal_entry_lines').select('*');

    query = query.eq('account_id', int.tryParse(accountId) ?? accountId);

    if (fromDate != null) {
      query = query.gte('transaction_date', AppUtils.formatDateForDb(fromDate));
    }
    if (toDate != null) {
      query = query.lte('transaction_date', AppUtils.formatDateForDb(toDate));
    }
    if (currency != null && currency.isNotEmpty && currency != 'ALL' && currency != 'الكل') {
      query = query.eq('currency', currency);
    }

    final data = await query
        .order('transaction_date', ascending: true)
        .order('created_at', ascending: true)
        .order('id', ascending: true);

    // Resolve account names if needed
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

    return (data as List).map((row) {
      final flat = Map<String, dynamic>.from(row as Map);
      final accId = flat['account_id']?.toString();
      final account = accId != null ? accountsMap[accId] : null;
      final accountModel = AccountModel.fromMap(account ?? {});

      final acCode = flat['account_code']?.toString();
      final acName = flat['account_name']?.toString();

      return {
        'id': flat['id']?.toString(),
        'date': flat['transaction_date']?.toString() ?? '',
        'entry_number': flat['entry_number']?.toString() ?? '',
        'account_id': flat['account_id']?.toString(),
        'account_code': (acCode != null && acCode.isNotEmpty) ? acCode : accountModel.code,
        'account_name': (acName != null && acName.isNotEmpty) ? acName : accountModel.displayName,
        'description': flat['description']?.toString() ?? '',
        'debit': (flat['debit'] as num?)?.toDouble() ?? 0.0,
        'credit': (flat['credit'] as num?)?.toDouble() ?? 0.0,
        'amount_in_base_currency': (flat['amount_in_base_currency'] as num?)?.toDouble(),
        'currency': flat['currency']?.toString() ?? 'EGP',
        'reference_type': flat['source_type']?.toString() ?? '',
        'reference_id': flat['source_id']?.toString() ?? '',
        'created_at': flat['created_at']?.toString() ?? '',
      };
    }).toList();
  }

  /// Build a display-friendly description from raw entry data
  String _buildDescription(Map<String, dynamic> raw) {
    final desc = raw['description']?.toString() ?? '';
    if (desc.isNotEmpty) return desc;

    // Fallback description from reference type
    final refType = raw['reference_type']?.toString() ?? '';
    switch (refType.toLowerCase()) {
      case 'opening_balance':
        return 'رصيد افتتاحي';
      case 'purchase_invoice':
      case 'purchase':
        return 'فاتورة مشتريات';
      case 'purchase_return':
        return 'مرتجع مشتريات';
      case 'supplier_payment':
        return 'سداد مورد';
      case 'sales_invoice':
      case 'invoice':
        return 'فاتورة مبيعات';
      case 'manual':
      case 'manual_journal':
        return 'قيد يدوي';
      default:
        return 'قيد محاسبي';
    }
  }

  /// Detect the dominant currency from entries
  String _detectCurrency(List<AccountLedgerEntry> entries) {
    if (entries.isEmpty) return 'EGP';
    // Use the currency of the first entry (all entries for a leaf account
    // should have the same currency)
    final currencies = <String, int>{};
    for (final e in entries) {
      currencies[e.currency] = (currencies[e.currency] ?? 0) + 1;
    }
    // Return the most common currency
    final sorted = currencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }
}
