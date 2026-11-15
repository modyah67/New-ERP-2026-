import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/tenant_service.dart';
import '../models/cost_center.dart';

/// OpeningBalanceGlSyncService
///
/// Ensures all entity opening balances (customers, suppliers, shareholders,
/// clearing agents, shipping companies, transport suppliers) are mirrored
/// into General Ledger (journal_entries and account_ledger_entries) and thus
/// accurately reflected in the Chart of Accounts tree and Account Statements.
class OpeningBalanceGlSyncService {
  static final OpeningBalanceGlSyncService instance = OpeningBalanceGlSyncService._();
  OpeningBalanceGlSyncService._();
  factory OpeningBalanceGlSyncService() => instance;

  SupabaseClient get _client => Supabase.instance.client;

  /// Resolve the opening balance equity account (23421 or parent 2342)
  Future<int?> resolveEquityAccountId(String currency, String? companyId) async {
    try {
      var query = _client
          .from('accounts')
          .select('id, account_code')
          .inFilter('account_code', ['23421', '2342', '2331', '3001']);

      if (companyId != null && companyId.isNotEmpty) {
        query = query.or('company_id.eq.$companyId,company_id.is.null,company_id.eq.a0000000-0000-0000-0000-000000000001');
      }

      final res = await query.order('account_code', ascending: false);
      if (res.isNotEmpty) {
        return (res.first['id'] as num).toInt();
      }

      // Robust fallback without company_id filter
      final fallback = await _client
          .from('accounts')
          .select('id, account_code')
          .inFilter('account_code', ['23421', '2342', '2331', '3001'])
          .order('account_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (fallback != null && fallback['id'] != null) {
        return (fallback['id'] as num).toInt();
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: resolveEquityAccountId error: $e');
    }
    return null;
  }

  /// Get exchange rate to EGP for a given currency
  Future<double> getExchangeRate(String currency) async {
    final cur = currency.trim().toUpperCase();
    if (cur == 'EGP' || cur == 'ج.م' || cur.isEmpty) return 1.0;

    try {
      final res = await _client
          .from('exchange_rates')
          .select('rate_to_egp')
          .eq('currency_code', cur)
          .order('id', ascending: false)
          .limit(1);

      if (res.isNotEmpty) {
        final rate = (res.first['rate_to_egp'] as num?)?.toDouble();
        if (rate != null && rate > 0) return rate;
      }
    } catch (_) {}

    if (cur == 'USD') return 50.0;
    if (cur == 'EUR') return 55.0;
    if (cur == 'GBP') return 65.0;
    return 1.0;
  }

  /// Resolve master Level-5 summary account ID for suppliers:
  /// - packaging ('packaging', 'sticker') -> 21112 ("موردي مواد التعبئة")
  /// - crop ('crop', default) -> 21113 ("موردي مشتريات محاصيل")
  /// - shared ('shared') -> 21114 ("موردين مشتركين")
  /// - transport ('transport') -> 21111 ("موردي النقل والسيارات")
  /// - shipping ('shipping') -> 21115 ("شركات الشحن")
  /// - clearing ('clearing', 'customs') -> 21116 ("مخلصي الجمارك")
  Future<int?> resolveSupplierAccountId({
    required String? supplierType,
    String? code,
    String? category,
    String? companyId,
  }) async {
    final cleanType = (supplierType ?? '').trim().toLowerCase();
    final cleanCode = (code ?? '').trim();
    final cleanCat = (category ?? '').trim().toLowerCase();

    final String targetCode;
    if (cleanType == 'station' || cleanCat.contains('محطة') || cleanCat.contains('محطات') || cleanCode.startsWith('8')) {
      targetCode = '21117';
    } else if (cleanType == 'deduction' || cleanType == 'deductions' || cleanCat.contains('تخصيم') || cleanCat.contains('تخصيمات') || cleanCode.startsWith('4')) {
      targetCode = '21118';
    } else if (cleanType == 'packaging' || cleanType == 'sticker' ||
        cleanCat.contains('packaging') || cleanCat.contains('تعبئة') || cleanCat.contains('كرتون') ||
        cleanCode.startsWith('70') || cleanCode.startsWith('71') || cleanCode.startsWith('72') || cleanCode.startsWith('73') || cleanCode.startsWith('74')) {
      targetCode = '21112';
    } else if (cleanType == 'shared' || cleanCat.contains('shared') || cleanCat.contains('مشترك') ||
        cleanCode.startsWith('75') || cleanCode.startsWith('76') || cleanCode.startsWith('77') || cleanCode.startsWith('78') || cleanCode.startsWith('79')) {
      targetCode = '21114';
    } else if (cleanType == 'transport' || cleanCode.startsWith('6')) {
      targetCode = '21111';
    } else if (cleanType == 'shipping' || cleanCode.startsWith('9')) {
      targetCode = '21115';
    } else if (cleanType == 'clearing' || cleanType == 'customs') {
      targetCode = '21116';
    } else {
      targetCode = '21113';
    }

    try {
      var query = _client.from('accounts').select('id').eq('account_code', targetCode);
      if (companyId != null && companyId.isNotEmpty) {
        query = query.or('company_id.eq.$companyId,company_id.is.null,company_id.eq.a0000000-0000-0000-0000-000000000001');
      }
      final res = await query.order('id', ascending: true).limit(1).maybeSingle();
      if (res != null && res['id'] != null) {
        return (res['id'] as num).toInt();
      }
      final fallback = await _client.from('accounts').select('id').eq('account_code', targetCode).limit(1).maybeSingle();
      return (fallback?['id'] as num?)?.toInt();
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: resolveSupplierAccountId error: $e');
      return null;
    }
  }

  /// Synchronize a customer's opening balance to GL
  Future<void> syncCustomerOpeningBalance({
    required dynamic customerId,
    required String customerName,
    required double initialBalance,
    required String currency,
    required String direction,
    required int? accountId,
    String? companyId,
    String? customerType,
  }) async {
    final cleanCompId = companyId ?? TenantService().tenantId;
    final sourceId = 'customers_$customerId';
    final desc = 'رصيد افتتاحي - $customerName';

    // 1. If initial balance is 0 or negative, remove existing journal entry
    if (initialBalance <= 0) {
      await _deleteExistingEntry(sourceId, cleanCompId);
      return;
    }

    // 2. Resolve customer account_id if not provided
    int? finalAccountId = accountId;
    if (finalAccountId == null) {
      final isLocal = (customerType ?? '').contains('local') || (customerType ?? '').contains('محلي');
      final targetCode = isLocal ? '12512' : '12511';
      final accRes = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', targetCode)
          .limit(1)
          .maybeSingle();
      finalAccountId = accRes?['id'] as int?;
    }

    if (finalAccountId == null) {
      debugPrint('OpeningBalanceGlSyncService: cannot resolve account_id for customer $customerName');
      return;
    }

    // 3. Resolve equity account (23421)
    final equityAccountId = await resolveEquityAccountId(currency, cleanCompId);
    if (equityAccountId == null) {
      debugPrint('OpeningBalanceGlSyncService: cannot resolve equity account 23421');
      return;
    }

    // 4. Calculate base amount
    final rate = await getExchangeRate(currency);
    final baseAmount = initialBalance * rate;

    // 5. Post or update Journal Entry
    await _postDoubleEntry(
      sourceId: sourceId,
      companyId: cleanCompId,
      description: desc,
      entityAccountId: finalAccountId,
      equityAccountId: equityAccountId,
      amount: initialBalance,
      baseAmount: baseAmount,
      currency: currency.toUpperCase(),
      direction: direction.toUpperCase(), // DEBIT for customer
    );
  }

  /// Synchronize a supplier's opening balance to GL (supports multi-currency and single currency)
  Future<void> syncSupplierOpeningBalance({
    required dynamic supplierId,
    required String supplierName,
    String? supplierCode,
    String? supplierType,
    String? category,
    required int? accountId,
    required bool isMultiCurrency,
    required double initialBalance,
    required String currency,
    required String direction,
    Map<String, dynamic>? initialBalancesByCurrency,
    String? companyId,
  }) async {
    final cleanCompId = companyId ?? TenantService().tenantId;
    final sourceId = 'suppliers_$supplierId';
    final desc = 'رصيد أول المدة للمورد: $supplierName';

    // 1. Resolve supplier Level-5 account
    int? finalAccountId = accountId;
    if (finalAccountId == null || finalAccountId == 0) {
      finalAccountId = await resolveSupplierAccountId(
        supplierType: supplierType,
        code: supplierCode,
        category: category,
        companyId: cleanCompId,
      );
    }

    if (finalAccountId == null) {
      debugPrint('OpeningBalanceGlSyncService: cannot resolve account_id for supplier $supplierName');
      return;
    }

    // 2. Resolve Equity Account (23421)
    final equityAccountId = await resolveEquityAccountId(currency, cleanCompId);
    if (equityAccountId == null) {
      debugPrint('OpeningBalanceGlSyncService: cannot resolve equity account 23421');
      return;
    }

    // 3. Multi-currency handling
    if (isMultiCurrency && initialBalancesByCurrency != null && initialBalancesByCurrency.isNotEmpty) {
      bool hasAnyBalance = false;
      for (final val in initialBalancesByCurrency.values) {
        if (val is Map) {
          final amt = (val['amount'] as num?)?.toDouble() ?? 0.0;
          if (amt > 0) hasAnyBalance = true;
        }
      }

      if (!hasAnyBalance) {
        await _deleteExistingEntry(sourceId, cleanCompId);
        return;
      }

      // Find or create Journal Entry
      final jeId = await _getOrCreateJournalEntryId(
        sourceId: sourceId,
        companyId: cleanCompId,
        description: desc,
        codePrefix: supplierCode,
      );

      // Clear existing ledger lines for this JE
      await _client.from('account_ledger_entries').delete().eq('journal_entry_id', jeId);

      // Insert balanced lines for each currency
      for (final entry in initialBalancesByCurrency.entries) {
        final cur = entry.key.toUpperCase();
        if (entry.value is! Map) continue;
        final item = Map<String, dynamic>.from(entry.value as Map);
        final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final dir = (item['direction']?.toString() ?? 'CREDIT').toUpperCase();
        double rate = (item['exchange_rate'] as num?)?.toDouble() ?? 0.0;
        if (rate <= 0) {
          rate = await getExchangeRate(cur);
        }
        final baseAmt = (item['amount_egp'] as num?)?.toDouble() ?? (amt * rate);

        if (amt > 0) {
          final isCredit = dir == 'CREDIT';

          // Entity Line (Supplier Sub-ledger 21112/21113/21114)
          await _client.from('account_ledger_entries').insert({
            'journal_entry_id': jeId,
            'account_id': finalAccountId,
            'debit': isCredit ? 0 : amt,
            'credit': isCredit ? amt : 0,
            'currency': cur,
            'amount_in_base_currency': baseAmt,
            'description': '$desc ($cur)',
            if (cleanCompId != null) 'company_id': cleanCompId,
          });

          // Equity Line (23421)
          await _client.from('account_ledger_entries').insert({
            'journal_entry_id': jeId,
            'account_id': equityAccountId,
            'debit': isCredit ? amt : 0,
            'credit': isCredit ? 0 : amt,
            'currency': cur,
            'amount_in_base_currency': baseAmt,
            'description': '$desc ($cur)',
            if (cleanCompId != null) 'company_id': cleanCompId,
          });
        }
      }
      debugPrint('OpeningBalanceGlSyncService: synced multi-currency supplier $supplierName to Acc $finalAccountId');
      return;
    }

    // 4. Single-currency handling
    if (initialBalance <= 0) {
      await _deleteExistingEntry(sourceId, cleanCompId);
      return;
    }

    final rate = await getExchangeRate(currency);
    final baseAmount = initialBalance * rate;

    await _postDoubleEntry(
      sourceId: sourceId,
      companyId: cleanCompId,
      description: desc,
      entityAccountId: finalAccountId,
      equityAccountId: equityAccountId,
      amount: initialBalance,
      baseAmount: baseAmount,
      currency: currency.toUpperCase(),
      direction: direction.toUpperCase(), // CREDIT for supplier
      codePrefix: supplierCode,
    );
  }

  /// Delete opening balance entry for an entity
  Future<void> deleteEntityOpeningBalance(String sourceId, String? companyId) async {
    final cleanCompId = companyId ?? TenantService().tenantId;
    await _deleteExistingEntry(sourceId, cleanCompId);
  }

  /// Delete existing opening balance journal entry for this source_id
  Future<void> _deleteExistingEntry(String sourceId, String? companyId) async {
    try {
      var query = _client
          .from('journal_entries')
          .select('id')
          .eq('source_type', 'opening_balance')
          .eq('source_id', sourceId);

      if (companyId != null && companyId.isNotEmpty) {
        query = query.eq('company_id', companyId);
      }

      final existingList = await query.order('id', ascending: false);
      for (final existing in existingList) {
        final jeId = existing['id'];
        await _client.from('account_ledger_entries').delete().eq('journal_entry_id', jeId);
        await _client.from('journal_entries').delete().eq('id', jeId);
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: _deleteExistingEntry error: $e');
    }
  }

  /// Helper to get or create journal entry ID
  Future<int> _getOrCreateJournalEntryId({
    required String sourceId,
    required String? companyId,
    required String description,
    String? codePrefix,
  }) async {
    var query = _client
        .from('journal_entries')
        .select('id, entry_number')
        .eq('source_type', 'opening_balance')
        .eq('source_id', sourceId);

    if (companyId != null && companyId.isNotEmpty) {
      query = query.eq('company_id', companyId);
    }

    final existingList = await query.order('id', ascending: false);
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    if (existingList.isNotEmpty) {
      final jeId = (existingList.first['id'] as num).toInt();
      await _client.from('journal_entries').update({
        'description': description,
        'status': 'posted',
        'entry_date': todayStr,
      }).eq('id', jeId);

      // Clean up any stale duplicate journal entries for this source_id
      if (existingList.length > 1) {
        for (int i = 1; i < existingList.length; i++) {
          final dupId = existingList[i]['id'];
          await _client.from('account_ledger_entries').delete().eq('journal_entry_id', dupId);
          await _client.from('journal_entries').delete().eq('id', dupId);
        }
      }

      return jeId;
    } else {
      String entryNumber = 'OB-00001';
      try {
        final seq = await _client.rpc('fn_get_next_sequence', params: {
          'p_company_id': companyId,
          'p_document_type_code': 'opening_balance',
        });
        if (seq != null && seq.toString().isNotEmpty) {
          entryNumber = seq.toString();
        }
      } catch (_) {
        entryNumber = 'OB-${codePrefix ?? (sourceId.split('_').last.length >= 5 ? sourceId.split('_').last.substring(0, 5) : sourceId.split('_').last)}';
      }

      final newJeList = await _client.from('journal_entries').insert({
        'source_type': 'opening_balance',
        'source_id': sourceId,
        'entry_number': entryNumber,
        'entry_date': todayStr,
        'description': description,
        'status': 'posted',
        if (companyId != null) 'company_id': companyId,
      }).select('id');

      if (newJeList.isNotEmpty) {
        return (newJeList.first['id'] as num).toInt();
      }
      throw Exception('Failed to create journal entry for source_id: $sourceId');
    }
  }

  /// Post or update double-entry journal entry and ledger lines
  Future<void> _postDoubleEntry({
    required String sourceId,
    required String? companyId,
    required String description,
    required int entityAccountId,
    required int equityAccountId,
    required double amount,
    required double baseAmount,
    required String currency,
    required String direction,
    String? codePrefix,
  }) async {
    try {
      final jeId = await _getOrCreateJournalEntryId(
        sourceId: sourceId,
        companyId: companyId,
        description: description,
        codePrefix: codePrefix,
      );

      await _client.from('account_ledger_entries').delete().eq('journal_entry_id', jeId);

      final bool isDebit = direction == 'DEBIT';

      // Line 1: Entity Account
      await _client.from('account_ledger_entries').insert({
        'journal_entry_id': jeId,
        'account_id': entityAccountId,
        'debit': isDebit ? amount : 0,
        'credit': isDebit ? 0 : amount,
        'currency': currency,
        'amount_in_base_currency': baseAmount,
        'description': description,
        if (companyId != null) 'company_id': companyId,
      });

      // Line 2: Equity Account (23421)
      await _client.from('account_ledger_entries').insert({
        'journal_entry_id': jeId,
        'account_id': equityAccountId,
        'debit': isDebit ? 0 : amount,
        'credit': isDebit ? amount : 0,
        'currency': currency,
        'amount_in_base_currency': baseAmount,
        'description': description,
        if (companyId != null) 'company_id': companyId,
      });

      debugPrint('OpeningBalanceGlSyncService: successfully synced opening balance to GL (JE: $jeId)');
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: _postDoubleEntry error: $e');
    }
  }

  /// Sync all existing customers in the database that have an initial balance > 0
  Future<void> syncAllCustomers() async {
    try {
      final customers = await _client
          .from('customers')
          .select('id, name, initial_balance, currency, initial_balance_direction, account_id, company_id, company_type')
          .gt('initial_balance', 0);

      for (final cust in customers) {
        final id = cust['id'];
        final name = cust['name']?.toString() ?? 'عميل';
        final initBal = (cust['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final cur = cust['currency']?.toString() ?? 'EGP';
        final dir = cust['initial_balance_direction']?.toString() ?? 'DEBIT';
        final accId = cust['account_id'] as int?;
        final compId = cust['company_id']?.toString();
        final cType = cust['company_type']?.toString();

        await syncCustomerOpeningBalance(
          customerId: id,
          customerName: name,
          initialBalance: initBal,
          currency: cur,
          direction: dir,
          accountId: accId,
          companyId: compId,
          customerType: cType,
        );
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: syncAllCustomers error: $e');
    }
  }

  /// Sync all existing suppliers in the database that have an initial balance
  Future<void> syncAllSuppliers() async {
    try {
      final suppliers = await _client.from('suppliers').select();
      for (final s in suppliers) {
        final id = s['id'];
        final name = s['name']?.toString() ?? 'مورد';
        final code = s['code']?.toString() ?? '';
        final type = s['supplier_type']?.toString();
        final cat = s['category']?.toString();
        final accId = s['account_id'] as int?;
        final isMulti = s['is_multi_currency'] == true;
        final initBal = (s['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final cur = s['currency']?.toString() ?? 'EGP';
        final dir = s['initial_balance_direction']?.toString() ?? 'CREDIT';
        final rawBalances = s['initial_balances_by_currency'];
        final balancesMap = (rawBalances is Map) ? Map<String, dynamic>.from(rawBalances) : null;
        final compId = s['company_id']?.toString();

        final hasNonZeroMultiCurrency = balancesMap != null &&
            balancesMap.values.any((v) => ((v as num?)?.toDouble() ?? 0.0).abs() > 0.001);

        // Optimization: skip suppliers that have no opening balance to avoid hundreds of redundant round-trips
        if (initBal <= 0 && !hasNonZeroMultiCurrency) {
          continue;
        }

        await syncSupplierOpeningBalance(
          supplierId: id,
          supplierName: name,
          supplierCode: code,
          supplierType: type,
          category: cat,
          accountId: accId,
          isMultiCurrency: isMulti,
          initialBalance: initBal,
          currency: cur,
          direction: dir,
          initialBalancesByCurrency: balancesMap,
          companyId: compId,
        );
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: syncAllSuppliers error: $e');
    }
  }

  /// Synchronize a cost center's opening balance to GL (Account 23421)
  Future<void> syncCostCenterOpeningBalance({
    required dynamic costCenterId,
    required String costCenterName,
    required String costCenterCode,
    required CostCenterType type,
    required double openingBalance,
    String currency = 'EGP',
    String? companyId,
    int? branchId,
  }) async {
    final cleanCompId = companyId ?? TenantService().tenantId;
    final cleanCode = costCenterCode.trim().isNotEmpty ? costCenterCode.trim() : costCenterId.toString();
    final sourceId = 'cost_center_$cleanCode';
    final desc = 'رصيد أول المدة لمركز التكلفة: $costCenterName';

    // 1. If balance <= 0, remove any existing entry
    if (openingBalance <= 0) {
      await _deleteExistingEntry(sourceId, cleanCompId);
      return;
    }

    // 2. Resolve Entity/Inventory/Expense Account:
    // Variety/crop lines: 12412 ("مخزن مشتريات خام" / مخزون المحاصيل)
    // Shipping: 5115 ("تكلفة شركات الشحن")
    // Customs Clearance: 5116 ("تكلفة المخلصين")
    // Transport & Logistics: 5117 ("لوجستيك ونقل")
    // Packaging: 5114 ("تعبئة وتغليف") or 12411
    final String targetAccountCode;
    if (type == CostCenterType.variety) {
      targetAccountCode = '12412';
    } else if (costCenterName.contains('شحن') || cleanCode == 'CC-CAT-4' || cleanCode == 'CC-LOGISTICS') {
      targetAccountCode = '5115';
    } else if (costCenterName.contains('تخليص') || costCenterName.contains('مخلص') || cleanCode == 'CC-CAT-5' || cleanCode == 'CC-CUSTOMS') {
      targetAccountCode = '5116';
    } else if (costCenterName.contains('لوجستيك') || costCenterName.contains('نقل') || cleanCode == 'CC-CAT-6') {
      targetAccountCode = '5117';
    } else if (costCenterName.contains('تعبئة') || costCenterName.contains('تغليف') || cleanCode == 'CC-CAT-3' || cleanCode == 'CC-PACKING') {
      targetAccountCode = '5114';
    } else {
      targetAccountCode = '12411';
    }

    int? entityAccountId;
    try {
      final accRes = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', targetAccountCode)
          .limit(1)
          .maybeSingle();
      if (accRes != null && accRes['id'] != null) {
        entityAccountId = (accRes['id'] as num).toInt();
      }
    } catch (_) {}

    if (entityAccountId == null) {
      try {
        final fallbackAcc = await _client
            .from('accounts')
            .select('id')
            .inFilter('account_code', ['12412', '1241', '124', '34111', '12411', '5114', '5115', '5116', '5117'])
            .order('account_code', ascending: false)
            .limit(1)
            .maybeSingle();
        if (fallbackAcc != null) {
          entityAccountId = (fallbackAcc['id'] as num).toInt();
        }
      } catch (_) {}
    }

    if (entityAccountId == null) {
      debugPrint('OpeningBalanceGlSyncService: cannot resolve account for cost center $costCenterName');
      return;
    }

    // 3. Resolve Equity Account (23421)
    final equityAccountId = await resolveEquityAccountId(currency, cleanCompId);
    if (equityAccountId == null) {
      debugPrint('OpeningBalanceGlSyncService: cannot resolve equity account 23421 for cost center $costCenterName');
      return;
    }

    // 4. Rate & Base Amount
    final rate = await getExchangeRate(currency);
    final baseAmount = openingBalance * rate;

    // 5. Post Double Entry:
    // Debit: Target inventory/cost account
    // Credit: 23421 (حساب وسيط الأرصدة الافتتاحية)
    await _postDoubleEntry(
      sourceId: sourceId,
      companyId: cleanCompId,
      description: desc,
      entityAccountId: entityAccountId,
      equityAccountId: equityAccountId,
      amount: openingBalance,
      baseAmount: baseAmount,
      currency: currency.toUpperCase(),
      direction: 'DEBIT', // Cost center inventory/cost asset is Debit, offsetting equity 23421 as Credit
      codePrefix: cleanCode,
    );
  }

  /// Sync all cost centers that have an opening balance > 0
  Future<void> syncAllCostCenters() async {
    try {
      final centers = await _client
          .from('cost_centers')
          .select('id, code, name, name_ar, cost_center_type, opening_balance, branch_id, company_id')
          .gt('opening_balance', 0);

      for (final c in centers) {
        final id = c['id'];
        final code = c['code']?.toString() ?? id.toString();
        final name = c['name_ar']?.toString() ?? c['name']?.toString() ?? code;
        final typeStr = c['cost_center_type']?.toString();
        final type = typeStr == 'operational' ? CostCenterType.operational : CostCenterType.variety;
        final ob = (c['opening_balance'] as num?)?.toDouble() ?? 0.0;
        final branchId = c['branch_id'] as int?;
        final compId = c['company_id']?.toString();

        if (ob > 0) {
          await syncCostCenterOpeningBalance(
            costCenterId: id,
            costCenterName: name,
            costCenterCode: code,
            type: type,
            openingBalance: ob,
            companyId: compId,
            branchId: branchId,
          );
        }
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: syncAllCostCenters error: $e');
    }
  }

  /// Sync all shipping companies with initial balance
  Future<void> syncAllShippingCompanies() async {
    try {
      final rows = await _client
          .from('shipping_companies')
          .select('id, name, code, initial_balance, currency')
          .gt('initial_balance', 0);
      for (final r in rows) {
        final id = r['id'];
        final name = r['name']?.toString() ?? 'شركة شحن';
        final code = r['code']?.toString() ?? 'SC-$id';
        final bal = (r['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final cur = r['currency']?.toString() ?? 'EGP';
        if (bal > 0) {
          await syncSupplierOpeningBalance(
            supplierId: id,
            supplierName: name,
            supplierCode: code,
            supplierType: 'shipping',
            category: 'shipping',
            accountId: null,
            isMultiCurrency: false,
            initialBalance: bal,
            direction: 'CREDIT',
            currency: cur,
          );
        }
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: syncAllShippingCompanies error: $e');
    }
  }

  /// Sync all clearing agents with initial balance
  Future<void> syncAllClearingAgents() async {
    try {
      final rows = await _client
          .from('clearing_agents')
          .select('id, name, code, initial_balance, currency')
          .gt('initial_balance', 0);
      for (final r in rows) {
        final id = r['id'];
        final name = r['name']?.toString() ?? 'مخلص جمركي';
        final code = r['code']?.toString() ?? 'CA-$id';
        final bal = (r['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final cur = r['currency']?.toString() ?? 'EGP';
        if (bal > 0) {
          await syncSupplierOpeningBalance(
            supplierId: id,
            supplierName: name,
            supplierCode: code,
            supplierType: 'customs',
            category: 'customs',
            accountId: null,
            isMultiCurrency: false,
            initialBalance: bal,
            direction: 'CREDIT',
            currency: cur,
          );
        }
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: syncAllClearingAgents error: $e');
    }
  }

  /// Sync all transport suppliers with initial balance
  Future<void> syncAllTransportSuppliers() async {
    try {
      final rows = await _client
          .from('transport_suppliers')
          .select('id, name, code, initial_balance, currency')
          .gt('initial_balance', 0);
      for (final r in rows) {
        final id = r['id'];
        final name = r['name']?.toString() ?? 'مورد نقل ولوجستيك';
        final code = r['code']?.toString() ?? 'TS-$id';
        final bal = (r['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final cur = r['currency']?.toString() ?? 'EGP';
        if (bal > 0) {
          await syncSupplierOpeningBalance(
            supplierId: id,
            supplierName: name,
            supplierCode: code,
            supplierType: 'transport',
            category: 'transport',
            accountId: null,
            isMultiCurrency: false,
            initialBalance: bal,
            direction: 'CREDIT',
            currency: cur,
          );
        }
      }
    } catch (e) {
      debugPrint('OpeningBalanceGlSyncService: syncAllTransportSuppliers error: $e');
    }
  }

  /// Sync all entities (customers, suppliers, shipping, clearing, transport, cost centers)
  Future<void> syncAllEntities() async {
    await syncAllCustomers();
    await syncAllSuppliers();
    await syncAllShippingCompanies();
    await syncAllClearingAgents();
    await syncAllTransportSuppliers();
    await syncAllCostCenters();
  }
}
