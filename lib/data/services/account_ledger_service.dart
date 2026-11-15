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
import '../models/cost_center.dart';

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
  /// [entityId] - Optional filter by entity UUID/ID (e.g. supplier ID) for shared accounts.
  /// [entityType] - Optional filter by entity type ('supplier', 'customer', etc.).
  ///
  /// Returns an [AccountLedgerResult] with pre-computed opening balance,
  /// running balances, totals, and deterministically sorted entries.
  Future<AccountLedgerResult> getAccountLedger({
    required List<String> accountIds,
    required String accountType,
    DateTime? fromDate,
    DateTime? toDate,
    String? currency,
    String? entityId,
    String? entityType,
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
          entityId: entityId,
          entityType: entityType,
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
      final rawDebit = (raw['debit'] as num?)?.toDouble() ?? 0.0;
      final rawCredit = (raw['credit'] as num?)?.toDouble() ?? 0.0;
      final rawCur = raw['currency']?.toString() ?? 'EGP';
      final isForeign = rawCur != 'EGP' && rawCur != 'ج.م' && rawCur.isNotEmpty;

      double debit = rawDebit;
      double credit = rawCredit;
      double? foreignDebit;
      double? foreignCredit;
      String? foreignCurrency;
      double? exchangeRate;

      if (isForeign) {
        foreignDebit = rawDebit > 0 ? rawDebit : null;
        foreignCredit = rawCredit > 0 ? rawCredit : null;
        foreignCurrency = rawCur;
      }

      if (isBaseMode) {
        final baseAmount = (raw['amount_in_base_currency'] as num?)?.toDouble() ?? (debit > 0 ? debit : credit);
        if (debit > 0) debit = baseAmount;
        if (credit > 0) credit = baseAmount;
        if (isForeign) {
          final origAmt = (rawDebit > 0 ? rawDebit : rawCredit);
          if (origAmt > 0 && baseAmount > 0) {
            exchangeRate = baseAmount / origAmt;
          }
        }
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
        costCenterId: raw['cost_center_id']?.toString(),
        costCenterName: raw['cost_center_name']?.toString() ??
            (raw['cost_center_id'] != null && raw['cost_center_id'].toString().isNotEmpty
                ? CostCenterHelper.fromId(raw['cost_center_id'].toString()).nameAr
                : null),
        createdAt: raw['created_at']?.toString() ?? '',
        foreignDebit: foreignDebit,
        foreignCredit: foreignCredit,
        foreignCurrency: foreignCurrency,
        exchangeRate: exchangeRate,
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
    String? entityId,
    String? entityType,
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

    // Filter by entityId if provided to protect shared sub-ledger control accounts
    final filteredRows = (data as List).where((row) {
      if (entityId == null || entityId.trim().isEmpty) return true;
      final targetId = entityId.trim().toLowerCase();
      final rowEntityId = (row['entity_id']?.toString() ?? '').trim().toLowerCase();
      // If row has an explicit entity_id, it must match
      if (rowEntityId.isNotEmpty && rowEntityId != 'null') {
        return rowEntityId == targetId;
      }
      return true;
    }).toList();

    // Lookup packing_order_cost_items to enrich descriptions for cost settlement entries
    final settlementOrderIds = <String>{};
    for (final row in filteredRows) {
      final sType = row['source_type']?.toString().toLowerCase();
      final sId = row['source_id']?.toString();
      if ((sType == 'packing_cost_settlement' || sType == 'cost_settlement') &&
          sId != null &&
          sId.isNotEmpty) {
        settlementOrderIds.add(sId);
      }
    }

    final Map<String, List<Map<String, dynamic>>> costItemsByOrderId = {};
    if (settlementOrderIds.isNotEmpty) {
      try {
        final costData = await _client
            .from('packing_order_cost_items')
            .select('id, packing_order_id, name, actual_amount, actual_quantity, actual_unit_price, detailed_notes, settlement_notes, invoice_ref')
            .inFilter('packing_order_id', settlementOrderIds.toList());
        for (final item in (costData as List)) {
          final m = Map<String, dynamic>.from(item as Map);
          final poId = m['packing_order_id']?.toString();
          if (poId != null) {
            costItemsByOrderId.putIfAbsent(poId, () => []).add(m);
          }
        }
      } catch (e) {
        debugPrint('AccountLedgerService: error fetching cost settlement notes: $e');
      }
    }

    return filteredRows.map((row) {
      final flat = Map<String, dynamic>.from(row as Map);
      final accId = flat['account_id']?.toString();
      final account = accId != null ? accountsMap[accId] : null;
      final accountModel = AccountModel.fromMap(account ?? {});

      final acCode = flat['account_code']?.toString();
      final acName = flat['account_name']?.toString();

      final ccId = flat['cost_center_id']?.toString();
      final rawCcName = flat['cost_center_name']?.toString();
      final ccName = (rawCcName != null && rawCcName.isNotEmpty)
          ? rawCcName
          : (ccId != null && ccId.isNotEmpty ? CostCenterHelper.fromId(ccId).nameAr : '');

      final sType = flat['source_type']?.toString().toLowerCase();
      final sId = flat['source_id']?.toString();
      final enrichedDesc = enrichCostSettlementLedgerDescription(
        rawDescription: flat['description']?.toString() ?? '',
        sourceType: sType,
        orderItems: sId != null ? costItemsByOrderId[sId] : null,
      );

      return {
        'id': flat['id']?.toString(),
        'date': flat['transaction_date']?.toString() ?? '',
        'entry_number': flat['entry_number']?.toString() ?? '',
        'account_id': flat['account_id']?.toString(),
        'account_code': (acCode != null && acCode.isNotEmpty) ? acCode : accountModel.code,
        'account_name': (acName != null && acName.isNotEmpty) ? acName : accountModel.displayName,
        'cost_center_id': ccId,
        'cost_center_name': ccName,
        'description': enrichedDesc,
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

  /// Enriches a general ledger entry description with detailed settlement notes
  /// from packing_order_cost_items when the database description is generic or incomplete.
  static String enrichCostSettlementLedgerDescription({
    required String rawDescription,
    required String? sourceType,
    List<Map<String, dynamic>>? orderItems,
  }) {
    String desc = rawDescription.trim();
    final sType = sourceType?.toLowerCase() ?? '';
    if ((sType != 'packing_cost_settlement' && sType != 'cost_settlement') ||
        orderItems == null ||
        orderItems.isEmpty) {
      return desc;
    }

    for (final item in orderItems) {
      final notes = (item['detailed_notes'] ??
              item['settlement_notes'] ??
              item['notes'])
          ?.toString()
          .trim();
      final invRef = item['invoice_ref']?.toString().trim();
      final itemName = item['name']?.toString().trim() ?? '';

      final matchesItem = orderItems.length == 1 ||
          (itemName.isNotEmpty && desc.contains(itemName));

      if (matchesItem) {
        if (notes != null && notes.isNotEmpty && !desc.contains(notes)) {
          desc = desc.isNotEmpty
              ? '$desc - $notes'
              : 'تسوية تكلفة فعلية${itemName.isNotEmpty ? ' ($itemName)' : ''} - $notes';
        }
        if (invRef != null && invRef.isNotEmpty && !desc.contains(invRef)) {
          desc = desc.isNotEmpty ? '$desc - مستند: $invRef' : 'مستند: $invRef';
        }
      }
    }
    return desc;
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
      case 'packing_order_costs':
      case 'packing_cost':
        return 'استحقاق تكلفة أمر تعبئة';
      case 'packing_cost_settlement':
      case 'cost_settlement':
        return 'تسوية تكلفة فعلية';
      case 'manual':
      case 'manual_journal':
        return 'قيد يدوي';
      default:
        return 'قيد محاسبي';
    }
  }
}
