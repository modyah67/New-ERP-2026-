import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/treasury_dao.dart';
import '../models/account_model.dart';
import '../models/purchase_model.dart';
import '../models/treasury_model.dart';
import '../../core/services/tenant_service.dart';

/// Dedicated enterprise service for managing employee cash custodies (العهد النقدية)
/// in accordance with Fruity Farms ERP accounting policies:
/// 1. Each employee's cash custody has a dedicated, independent Level-5 posting account
///    under 12612 (Temporary Cash Custody) or 12613 (Permanent Cash Custody).
/// 2. Cost centers remain strictly reserved for crops and agricultural activities,
///    and are never attached to employee custody accounts or inter-custody transfers.
/// 3. Individual employee balances reflect distinctly in the Trial Balance (ميزان المراجعة).
class CustodyService {
  final _client = Supabase.instance.client;
  final TreasuryDao _treasuryDao = TreasuryDao();

  void _log(String msg) => debugPrint('💼 CustodyService: $msg');

  /// Automatically ensures that a dedicated Level-5 account exists in the Chart
  /// of Accounts (under 12612 or 12613) for the given employee custody treasury.
  ///
  /// Returns the assigned account ID.
  Future<int?> ensureCustodyAccount({
    required String treasuryId,
    String? companyId,
  }) async {
    try {
      final tenantId = companyId ?? TenantService().tenantId;
      final res = await _client.rpc('ensure_custody_account', params: {
        'p_treasury_id': int.tryParse(treasuryId) ?? treasuryId,
        if (tenantId != null) 'p_company_id': tenantId,
      });

      _log('ensureCustodyAccount: treasuryId=$treasuryId -> accountId=$res');
      if (res is int) return res;
      return int.tryParse('$res');
    } catch (e) {
      _log('ensureCustodyAccount error: $e');
      rethrow;
    }
  }

  /// Retrieves the dedicated Level-5 account model linked to an employee custody treasury.
  Future<AccountModel?> getCustodyAccount(String treasuryId) async {
    try {
      final treasury = await _treasuryDao.getById(treasuryId);
      if (treasury == null) return null;

      var accountId = treasury.accountId;
      if (accountId == null) {
        final ensured = await ensureCustodyAccount(treasuryId: treasuryId);
        accountId = ensured?.toString();
      }

      if (accountId == null) return null;

      final data = await _client
          .from('accounts')
          .select()
          .eq('id', accountId)
          .maybeSingle();

      if (data == null) return null;
      return AccountModel.fromMap(Map<String, dynamic>.from(data));
    } catch (e) {
      _log('getCustodyAccount error: $e');
      return null;
    }
  }

  /// Creates a new employee custody with automated Level-5 Chart of Accounts provisioning.
  Future<TreasuryModel> createCustody({
    required String name,
    required String employeeId,
    String? notes,
    bool isPermanent = false,
  }) async {
    _log('createCustody: name=$name employeeId=$employeeId isPermanent=$isPermanent');
    
    final finalNotes = [
      if (isPermanent) 'عهدة مستديمة',
      if (notes != null && notes.trim().isNotEmpty) notes.trim(),
    ].join(' - ');

    final treasury = await _treasuryDao.createTreasury(
      name: name,
      type: 'employee',
      employeeId: employeeId,
      notes: finalNotes.isNotEmpty ? finalNotes : null,
    );

    // Explicitly guarantee Level-5 account assignment
    final tId = treasury.id;
    if (tId != null) {
      await ensureCustodyAccount(treasuryId: tId);
      final refreshed = await _treasuryDao.getById(tId);
      if (refreshed != null) return refreshed;
    }
    return treasury;
  }

  /// Disburses funds from Main Treasury to an Employee Custody Treasury.
  ///
  /// The transaction binds directly to the employee's dynamic Level-5 account
  /// under 12612 / 12613.
  Future<void> disburseCustody({
    required String fromTreasuryId,
    required String toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    _log('disburseCustody: from=$fromTreasuryId to=$toTreasuryId amount=$amount $currency');
    await _treasuryDao.createDisbursement(
      fromTreasuryId: fromTreasuryId,
      toTreasuryId: toTreasuryId,
      currency: currency,
      amount: amount,
      description: description,
      notes: notes,
    );
  }

  /// Transfers funds from one employee custody to another.
  ///
  /// Cost centers remain isolated to agricultural/crop operational tracking.
  Future<void> transferCustody({
    required String fromTreasuryId,
    required String toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
    String? costCenterId,
    dynamic branchId,
    dynamic toBranchId,
    String? toCostCenterId,
  }) async {
    _log('transferCustody: from=$fromTreasuryId to=$toTreasuryId amount=$amount $currency');
    await _treasuryDao.transferCustody(
      fromTreasuryId: fromTreasuryId,
      toTreasuryId: toTreasuryId,
      currency: currency,
      amount: amount,
      description: description,
      notes: notes,
      costCenterId: costCenterId,
      branchId: branchId,
      toBranchId: toBranchId,
      toCostCenterId: toCostCenterId,
    );
  }

  /// Spends funds from an employee custody.
  ///
  /// Strictly reserves [costCenterId] for crops and agricultural activities on the
  /// debit expense line, while the custody credit line targets the employee's
  /// dedicated Level-5 account without cost center attachment.
  Future<void> spendCustody({
    required String treasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? ledgerDescription,
    String? expenseAccountId,
    String? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
    PurchaseModel? invoice,
    String? notes,
    String? costCenterId,
    dynamic branchId,
  }) async {
    _log('spendCustody: treasury=$treasuryId amount=$amount $currency cc=$costCenterId');
    await _treasuryDao.spend(
      treasuryId: treasuryId,
      currency: currency,
      amount: amount,
      description: description,
      ledgerDescription: ledgerDescription,
      expenseAccountId: expenseAccountId,
      customerId: customerId,
      supplierId: supplierId,
      clearingAgentId: clearingAgentId,
      shippingCompanyId: shippingCompanyId,
      shareholderId: shareholderId,
      invoice: invoice,
      notes: notes,
      costCenterId: costCenterId,
      branchId: branchId,
    );
  }

  /// Returns custody funds back to the Main Treasury.
  Future<void> returnCustody({
    required String fromTreasuryId,
    required String toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    _log('returnCustody: from=$fromTreasuryId to=$toTreasuryId amount=$amount $currency');
    await _client.rpc('return_custody', params: {
      'p_from_treasury_id': int.tryParse(fromTreasuryId) ?? fromTreasuryId,
      'p_to_treasury_id': int.tryParse(toTreasuryId) ?? toTreasuryId,
      'p_currency': currency,
      'p_amount': amount,
      'p_description': description,
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
    });
  }

  /// Ensures that the dedicated quick expense accounts (31123, 31124, 31125) exist in the database,
  /// and returns a map mapping account code to AccountModel.
  Future<Map<String, AccountModel>> getQuickCustodyExpenseAccounts({String? companyId}) async {
    final codes = ['31123', '31124', '31125'];
    final tenantId = companyId ?? TenantService().tenantId;

    try {
      final res = await _client
          .from('accounts')
          .select()
          .inFilter('account_code', codes);

      final Map<String, AccountModel> map = {};
      for (final m in (res as List)) {
        final acc = AccountModel.fromMap(Map<String, dynamic>.from(m as Map));
        map[acc.code] = acc;
      }

      // Check if any missing and auto-provision
      for (final item in QuickCustodyExpenseItem.defaultItems) {
        if (!map.containsKey(item.code)) {
          _log('Auto-provisioning quick expense account:  ()');
          final parentRes = await _client
              .from('accounts')
              .select('id')
              .eq('account_code', '3112')
              .maybeSingle();
          final parentId = parentRes?['id'];

          final inserted = await _client.from('accounts').insert({
            'account_code': item.code,
            'name': item.englishName,
            'account_name': item.title,
            'account_type': 'expense',
            'normal_balance': 'Debit',
            'is_active': true,
            'is_leaf': true,
            'allow_posting': true,
            'sort_order': item.sortOrder,
            'level': 5,
            if (parentId != null) 'parent_id': parentId,
            if (tenantId != null) 'company_id': tenantId,
          }).select().maybeSingle();

          if (inserted != null) {
            map[item.code] = AccountModel.fromMap(Map<String, dynamic>.from(inserted));
          }
        }
      }
      return map;
    } catch (e) {
      _log('getQuickCustodyExpenseAccounts error: ');
      return {};
    }
  }

  /// Computes the aggregate pool of operational expenses disbursed from all employee custodies,
  /// the total already allocated to packing orders, and the remaining available pool.
  /// Supports optional [fromDate] and [toDate] range filtering.
  Future<CustodyExpensePoolSummary> getCustodyExpensePoolSummary({
    int? excludePackingOrderId,
    String? companyId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      // 1. Fetch employee custody treasuries
      final treasuriesRes = await _client
          .from('treasuries')
          .select('id, name, type')
          .inFilter('type', ['employee', 'custody']);

      final custodyIds = (treasuriesRes as List)
          .map((t) => t['id'])
          .where((id) => id != null)
          .toList();

      double meals = 0.0;
      double labor = 0.0;
      double transport = 0.0;
      double other = 0.0;
      int txCount = 0;

      DateTime? startOfDay;
      DateTime? endOfDay;
      if (fromDate != null) {
        startOfDay = DateTime(fromDate.year, fromDate.month, fromDate.day, 0, 0, 0, 0);
      }
      if (toDate != null) {
        endOfDay = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
      }

      if (custodyIds.isNotEmpty) {
        // 2. Fetch all expense transactions from employee custodies
        var txsQuery = _client
            .from('treasury_transactions')
            .select('id, amount, currency, description, notes, category_id, payload, created_at')
            .inFilter('treasury_id', custodyIds)
            .inFilter('type', ['expense', 'expense_payment'])
            .neq('status', 'draft');

        if (startOfDay != null) {
          txsQuery = txsQuery.gte('created_at', startOfDay.toUtc().toIso8601String());
        }
        if (endOfDay != null) {
          txsQuery = txsQuery.lte('created_at', endOfDay.toUtc().toIso8601String());
        }

        final txsRes = await txsQuery;

        for (final tx in (txsRes as List)) {
          // In-memory verification with local time
          if (startOfDay != null || endOfDay != null) {
            final rawDate = tx['created_at'];
            if (rawDate != null) {
              final txDate = DateTime.tryParse(rawDate.toString())?.toLocal();
              if (txDate != null) {
                if (startOfDay != null && txDate.isBefore(startOfDay)) continue;
                if (endOfDay != null && txDate.isAfter(endOfDay)) continue;
              }
            }
          }

          final amt = ((tx['amount'] ?? 0) as num).toDouble().abs();
          if (amt <= 0) continue;
          txCount++;

          final desc = (tx['description']?.toString() ?? '').toLowerCase();
          final notes = (tx['notes']?.toString() ?? '').toLowerCase();
          final payload = tx['payload'];
          String payloadText = '';
          if (payload is Map) {
            payloadText = payload.values.map((v) => v.toString()).join(' ').toLowerCase();
          }
          final fullText = '$desc $notes $payloadText';

          // Strictly filter for the 3 allowed packing custody expense branches:
          // 1. وجبات وأغذية (Meals - 31124)
          // 2. عمالة مؤقتة ويومية (Temporary Labor - 31125)
          // 3. انتقالات ومصروفات نقدية (Staff Transport & Expenses - 31123)
          final isMeal = fullText.contains('وجب') ||
              fullText.contains('طعام') ||
              fullText.contains('أغذ') ||
              fullText.contains('31124');
          final isLabor = fullText.contains('عمال') ||
              fullText.contains('أجور') ||
              fullText.contains('يومي') ||
              fullText.contains('31125');
          final isTransport = fullText.contains('نقل') ||
              fullText.contains('انتقال') ||
              fullText.contains('مواص') ||
              fullText.contains('31123') ||
              fullText.contains('مصروفات نقدية');

          if (isMeal) {
            meals += amt;
            txCount++;
          } else if (isLabor) {
            labor += amt;
            txCount++;
          } else if (isTransport) {
            transport += amt;
            txCount++;
          } else {
            // Other branches (administrative, marketing, etc.) spent from the custody
            // are strictly excluded from the packing order cost pool
            other += amt;
          }
        }
      }

      // Total spent for the packing order custody pool is strictly restricted
      // to the 3 main expenses: (Labor, Meals, Staff Transport/Expenses).
      final totalSpent = meals + labor + transport;

      // 3. Fetch already allocated engineer costs from packing orders
      double totalAllocated = 0.0;
      int allocatedOrdersCount = 0;
      final Set<dynamic> ordersWithDbItems = {};

      try {
        var query = _client
            .from('packing_order_cost_items')
            .select('id, packing_order_id, base_amount, category, name, created_at')
            .isFilter('deleted_at', null);
        if (excludePackingOrderId != null) {
          query = query.neq('packing_order_id', excludePackingOrderId);
        }
        if (startOfDay != null) {
          query = query.gte('created_at', startOfDay.toUtc().toIso8601String());
        }
        if (endOfDay != null) {
          query = query.lte('created_at', endOfDay.toUtc().toIso8601String());
        }
        final itemsRes = await query;
        for (final item in (itemsRes as List)) {
          if (startOfDay != null || endOfDay != null) {
            final rawDate = item['created_at'];
            if (rawDate != null) {
              final itemDate = DateTime.tryParse(rawDate.toString())?.toLocal();
              if (itemDate != null) {
                if (startOfDay != null && itemDate.isBefore(startOfDay)) continue;
                if (endOfDay != null && itemDate.isAfter(endOfDay)) continue;
              }
            }
          }

          final ordId = item['packing_order_id'];
          if (ordId != null) ordersWithDbItems.add(ordId);
          final cat = (item['category']?.toString() ?? '').toLowerCase();
          final name = (item['name']?.toString() ?? '').toLowerCase();
          if (cat == 'engineer_expenses' || cat == 'engineer' || name.contains('مهندس') || name.contains('إشراف') || name.contains('اشراف')) {
            totalAllocated += ((item['base_amount'] ?? 0) as num).toDouble();
            allocatedOrdersCount++;
          }
        }
      } catch (e) {
        _log('Warning querying packing_order_cost_items: $e');
      }

      try {
        var orderQuery = _client.from('packing_orders').select('id, notes, created_at');
        if (excludePackingOrderId != null) {
          orderQuery = orderQuery.neq('id', excludePackingOrderId);
        }
        if (startOfDay != null) {
          orderQuery = orderQuery.gte('created_at', startOfDay.toUtc().toIso8601String());
        }
        if (endOfDay != null) {
          orderQuery = orderQuery.lte('created_at', endOfDay.toUtc().toIso8601String());
        }
        final ordersRes = await orderQuery;
        for (final order in (ordersRes as List)) {
          if (startOfDay != null || endOfDay != null) {
            final rawDate = order['created_at'];
            if (rawDate != null) {
              final oDate = DateTime.tryParse(rawDate.toString())?.toLocal();
              if (oDate != null) {
                if (startOfDay != null && oDate.isBefore(startOfDay)) continue;
                if (endOfDay != null && oDate.isAfter(endOfDay)) continue;
              }
            }
          }
          final oId = order['id'];
          if (ordersWithDbItems.contains(oId) || ordersWithDbItems.contains(int.tryParse('$oId'))) {
            continue;
          }
          final oNotes = order['notes'];
          if (oNotes == null) continue;
          try {
            final nMap = oNotes is Map ? oNotes : jsonDecode(oNotes.toString());
            final costItems = nMap['cost_items'] as List?;
            if (costItems != null) {
              for (final ci in costItems) {
                final cat = (ci['category']?.toString() ?? '').toLowerCase();
                final name = (ci['name']?.toString() ?? '').toLowerCase();
                if (cat == 'engineer_expenses' || cat == 'engineer' || name.contains('مهندس') || name.contains('إشراف') || name.contains('اشراف')) {
                  final amt = ((ci['total_egp'] ?? ci['total'] ?? 0) as num).toDouble();
                  if (amt > 0) {
                    totalAllocated += amt;
                    allocatedOrdersCount++;
                  }
                }
              }
            }
          } catch (_) {}
        }
      } catch (e) {
        _log('Warning querying packing_orders notes: $e');
      }

      final remaining = (totalSpent - totalAllocated).clamp(0.0, double.infinity);

      return CustodyExpensePoolSummary(
        totalSpent: totalSpent,
        totalAllocated: totalAllocated,
        remainingPool: remaining,
        mealsSpent: meals,
        laborSpent: labor,
        transportSpent: transport,
        otherSpent: other,
        transactionsCount: txCount,
        allocatedOrdersCount: allocatedOrdersCount,
        fromDate: fromDate,
        toDate: toDate,
      );
    } catch (e, st) {
      _log('getCustodyExpensePoolSummary error: $e\n$st');
      return const CustodyExpensePoolSummary();
    }
  }
}

/// Structured summary of the operational custody expense pool and its allocation state.
class CustodyExpensePoolSummary {
  final double totalSpent;
  final double totalAllocated;
  final double remainingPool;
  final double mealsSpent;
  final double laborSpent;
  final double transportSpent;
  final double otherSpent;
  final int transactionsCount;
  final int allocatedOrdersCount;
  final DateTime? fromDate;
  final DateTime? toDate;

  const CustodyExpensePoolSummary({
    this.totalSpent = 0.0,
    this.totalAllocated = 0.0,
    this.remainingPool = 0.0,
    this.mealsSpent = 0.0,
    this.laborSpent = 0.0,
    this.transportSpent = 0.0,
    this.otherSpent = 0.0,
    this.transactionsCount = 0,
    this.allocatedOrdersCount = 0,
    this.fromDate,
    this.toDate,
  });

  /// Helper to calculate the allocation amount from either a cash amount or a percentage.
  double calculateAmount({
    required bool isPercentage,
    required double inputValue,
  }) {
    if (inputValue <= 0) return 0.0;
    if (isPercentage) {
      final pct = inputValue.clamp(0.0, 100.0);
      return (remainingPool * (pct / 100.0));
    }
    return inputValue;
  }

  /// Helper to calculate remaining balance after allocating an amount.
  double remainingAfter(double amountToAllocate) {
    return math.max(0.0, remainingPool - amountToAllocate);
  }
}

/// Dedicated representation of a quick custody expense category.
class QuickCustodyExpenseItem {
  final String code;
  final String title;
  final String defaultDescription;
  final String englishName;
  final int sortOrder;

  const QuickCustodyExpenseItem({
    required this.code,
    required this.title,
    required this.defaultDescription,
    required this.englishName,
    required this.sortOrder,
  });

  static const List<QuickCustodyExpenseItem> defaultItems = [
    QuickCustodyExpenseItem(
      code: '31123',
      title: 'مصروفات انتقالات',
      defaultDescription: 'انتقالات ومواصلات',
      englishName: 'Staff Transportation Expense',
      sortOrder: 31123,
    ),
    QuickCustodyExpenseItem(
      code: '31124',
      title: 'وجبات',
      defaultDescription: 'وجبات طاقم العمل',
      englishName: 'Staff Meals Expense',
      sortOrder: 31124,
    ),
    QuickCustodyExpenseItem(
      code: '31125',
      title: 'عمالة',
      defaultDescription: 'أجور عمالة يومية',
      englishName: 'Temporary Labor Expense',
      sortOrder: 31125,
    ),
  ];
}
