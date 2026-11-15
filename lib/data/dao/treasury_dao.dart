import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/treasury_model.dart';
import '../models/user_model.dart';
import '../models/expense_category_model.dart';
import '../models/treasury_stats_model.dart';
import '../models/purchase_model.dart';
import '../services/currency_conversion_service.dart';
import '../services/supplier_settlement_service.dart';
import '../services/purchase_invoice_service.dart';
import '../services/chart_of_accounts_service.dart';
import '../services/treasury_account_resolver.dart';
import '../../core/services/tenant_service.dart';
import 'transaction_dao.dart';
import 'financial_audit_log_dao.dart';

class TreasuryDao {
  final _client = Supabase.instance.client;

  // ── Constants ──

  static const List<String> supportedCurrencies = ['EGP', 'USD', 'EUR', 'GBP'];
  static const String _tag = 'TreasuryDao';

  void _log(String msg) => debugPrint('💰 TreasuryDao: $msg');

  // ── Queries ──

  Future<List<TreasuryModel>> getAll() async {
    try {
      final data = await _client
          .from('treasuries')
          .select('*, balances:treasury_balances(*)')
          .order('type', ascending: true)
          .order('name');

      _log('getAll: ${data.length} treasury(ies)');

      return data.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return TreasuryModel.fromMap(map);
      }).toList();
    } catch (e, st) {
      _log('getAll error: $e\n$st');
      rethrow;
    }
  }

  Future<TreasuryModel?> getById(String id) async {
    try {
      final data = await _client
          .from('treasuries')
          .select('*, balances:treasury_balances(*)')
          .eq('id', id)
          .maybeSingle();

      if (data == null) return null;
      final map = Map<String, dynamic>.from(data as Map);
      return TreasuryModel.fromMap(map);
    } catch (e, st) {
      _log('getById error: $e\n$st');
      rethrow;
    }
  }

  Future<List<TreasuryModel>> getAllByUserId(String userId) async {
    try {
      final data = await _client
          .from('treasuries')
          .select('*, balances:treasury_balances(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (data == null) return [];
      return (data as List).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return TreasuryModel.fromMap(map);
      }).toList();
    } catch (e, st) {
      _log('getAllByUserId error: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTransactionsForExport({
    required int treasuryId,
    String? currency,
    String? typeFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client
          .from('treasury_transactions')
          .select(
              '*, treasuries!treasury_id(name), related:treasury_transactions_related_treasury_id_fkey(name), expense_categories!category_id(name,color), created_by_user:users!created_by(full_name), suppliers!supplier_id(name), customers!customer_id(name), clearing_agents!clearing_agent_id(name), shipping_companies!shipping_company_id(name), shareholders!shareholder_id(name), journal_entry_id, journal_entries(entry_number)')
          .eq('treasury_id', treasuryId);

      if (currency != null && currency.isNotEmpty) {
        query = query.eq('currency', currency);
      }
      if (typeFilter != null && typeFilter.isNotEmpty) {
        query = query.eq('type', typeFilter);
      }
      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }

      final data = await query.order('created_at', ascending: false);
      return (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      _log('getTransactionsForExport error: $e\n$st');
      rethrow;
    }
  }

  Future<List<TreasuryTransactionModel>> getTransactions(
    String treasuryId, {
    int limit = 50,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
  }) async {
    try {
      var query = _client
          .from('treasury_transactions')
          .select(
              '*, treasuries!treasury_id(name), related:treasury_transactions_related_treasury_id_fkey(name), expense_categories!category_id(name,color), created_by_user:users!created_by(full_name), suppliers!supplier_id(name), customers!customer_id(name), clearing_agents!clearing_agent_id(name), shipping_companies!shipping_company_id(name), shareholders!shareholder_id(name), journal_entry_id, journal_entries(entry_number)')
          .eq('treasury_id', treasuryId);
          
      if (startDate != null) query = query.gte('created_at', startDate.toIso8601String());
      if (endDate != null) query = query.lte('created_at', endDate.toIso8601String());
      if (currency != null) query = query.eq('currency', currency);

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      _log('getTransactions($treasuryId): ${data.length} tx(s)');

      return data.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return TreasuryTransactionModel.fromMap(map);
      }).toList();
    } catch (e, st) {
      _log('getTransactions error: $e\n$st');
      rethrow;
    }
  }

  Future<List<TreasuryTransactionModel>> getAllTransactions({
    int limit = 100,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client
          .from('treasury_transactions')
          .select(
              '*, treasuries!treasury_id(name), related:treasury_transactions_related_treasury_id_fkey(name), expense_categories!category_id(name,color), created_by_user:users!created_by(full_name), suppliers!supplier_id(name), customers!customer_id(name), clearing_agents!clearing_agent_id(name), shipping_companies!shipping_company_id(name), shareholders!shareholder_id(name), journal_entry_id, journal_entries(entry_number)');

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return data.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return TreasuryTransactionModel.fromMap(map);
      }).toList();
    } catch (e, st) {
      _log('getAllTransactions error: $e\n$st');
      rethrow;
    }
  }

  // ── Expense Categories ──

  Future<List<ExpenseCategoryModel>> getExpenseCategories() async {
    try {
      final data =
          await _client.from('expense_categories').select().order('name');

      return (data as List).map((e) {
        return ExpenseCategoryModel.fromMap(Map<String, dynamic>.from(e));
      }).toList();
    } catch (e, st) {
      _log('getExpenseCategories error: $e\n$st');
      return [];
    }
  }

  Future<List<ExpenseCategoryModel>> getActiveExpenseCategories() async {
    try {
      final data = await _client
          .from('expense_categories')
          .select()
          .eq('is_active', true)
          .order('name');

      return (data as List).map((e) {
        return ExpenseCategoryModel.fromMap(Map<String, dynamic>.from(e));
      }).toList();
    } catch (e, st) {
      _log('getActiveExpenseCategories error: $e\n$st');
      return [];
    }
  }

  Future<ExpenseCategoryModel> createExpenseCategory({
    required String name,
    required String color,
    required String currency,
  }) async {
    try {
      final newId = await _client.rpc('create_expense_category', params: {
        'p_name': name,
        'p_color': color,
        'p_currency': currency,
      });

      return ExpenseCategoryModel(
        id: newId.toString(),
        name: name,
        color: color,
        currency: currency,
      );
    } catch (e) {
      _log('RPC create_expense_category failed, falling back: $e');
      final err = e.toString();
      if (err.contains('23505') || err.contains('expense_categories_name') || err.contains('idx_expense_categories_name')) {
        throw Exception('يوجد تصنيف بهذا الاسم بالفعل');
      }
      try {
        final data = await _client
            .from('expense_categories')
            .insert({
              'name': name,
              'color': color,
              'currency': currency,
              'created_by': _client.auth.currentUser?.id,
            })
            .select()
            .single();
        return ExpenseCategoryModel.fromMap(Map<String, dynamic>.from(data));
      } catch (e2) {
        final err2 = e2.toString();
        if (err2.contains('23505') || err2.contains('expense_categories_name') || err2.contains('idx_expense_categories_name')) {
          throw Exception('يوجد تصنيف بهذا الاسم بالفعل');
        }
        rethrow;
      }
    }
  }

  Future<void> updateExpenseCategory({
    required String id,
    String? name,
    String? color,
    String? currency,
    bool? isActive,
  }) async {
    try {
      await _client.rpc('update_expense_category', params: {
        'p_id': id,
        if (name != null) 'p_name': name,
        if (color != null) 'p_color': color,
        if (currency != null) 'p_currency': currency,
        if (isActive != null) 'p_is_active': isActive,
      });
    } catch (e) {
      _log('RPC update_expense_category failed, falling back: $e');
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (color != null) updates['color'] = color;
      if (currency != null) updates['currency'] = currency;
      if (isActive != null) updates['is_active'] = isActive;
      await _client.from('expense_categories').update(updates).eq('id', id);
    }
  }

  Future<void> deleteExpenseCategory(String id) async {
    try {
      await _client.rpc('delete_expense_category', params: {'p_id': id});
    } catch (e) {
      _log('RPC delete_expense_category failed, falling back: $e');
      await _client
          .from('treasury_transactions')
          .update({'category_id': null}).eq('category_id', id);
      await _client.from('expense_categories').delete().eq('id', id);
    }
  }

  // ── Treasury Stats ──

  Future<TreasuryStatsModel> getTreasuryStats({
    required String mainTreasuryId,
    bool allTreasuries = false,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_main_treasury_id': mainTreasuryId,
        'p_all_treasuries': allTreasuries,
      };
      if (startDate != null) params['p_start_date'] = startDate;
      if (endDate != null) params['p_end_date'] = endDate;

      final result = await _client.rpc('get_treasury_stats', params: params);
      final map = Map<String, dynamic>.from(result as Map);

      // Fetch per-currency breakdowns from treasury_transactions
      var query = _client.from('treasury_transactions').select('currency, type, amount');
      if (!allTreasuries) {
        query = query.eq('treasury_id', mainTreasuryId);
      }
      if (startDate != null) {
        query = query.gte('created_at', startDate);
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate);
      }

      final txData = await query;
      final txList = (txData as List).cast<Map<String, dynamic>>();

      final Map<String, double> expensesMap = {};
      final Map<String, double> disbursementsMap = {};
      final Map<String, double> depositsMap = {};

      for (final tx in txList) {
        final currency = tx['currency']?.toString() ?? 'EGP';
        final type = tx['type']?.toString() ?? '';
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;

        if (type == 'withdrawal' || type == 'expense' || type == 'supplier_payment') {
          expensesMap[currency] = (expensesMap[currency] ?? 0) + amount;
        } else if (type == 'disbursement' || type == 'disbursement_out') {
          disbursementsMap[currency] = (disbursementsMap[currency] ?? 0) + amount;
        } else if (type == 'deposit') {
          depositsMap[currency] = (depositsMap[currency] ?? 0) + amount;
        }
      }

      map['expenses_by_currency'] = expensesMap.entries
          .map((e) => {'currency': e.key, 'total': e.value})
          .toList();
      map['disbursements_by_currency'] = disbursementsMap.entries
          .map((e) => {'currency': e.key, 'total': e.value})
          .toList();
      map['deposits_by_currency'] = depositsMap.entries
          .map((e) => {'currency': e.key, 'total': e.value})
          .toList();

      return TreasuryStatsModel.fromJson(map);
    } catch (e, st) {
      _log('getTreasuryStats error: $e\n$st');
      rethrow;
    }
  }

  Future<bool> hasOwnerSafePermission() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final data = await _client
          .from('user_roles')
          .select('allowed_pages')
          .eq('user_id', userId)
          .maybeSingle();
      if (data == null || data['allowed_pages'] == null) return false;
      final pages = (data['allowed_pages'] as List).map((e) => e.toString()).toList();
      return pages.contains('/owner-safe');
    } catch (_) {
      return false;
    }
  }

  // ── Operations ──

  /// Create a new treasury (admin only).
  Future<TreasuryModel> createTreasury({
    required String name,
    required String type,
    String? employeeId,
    String? notes,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_name': name,
        'p_type': type,
      };
      
      final companyId = TenantService().tenantId;
      if (companyId != null) {
        params['p_company_id'] = companyId;
      }
      
      if (employeeId != null) params['p_employee_id'] = employeeId;
      if (notes != null && notes.isNotEmpty) params['p_notes'] = notes;

      dynamic newId;
      try {
        newId = await _client.rpc('create_treasury', params: params);
        _log('createTreasury via RPC: OK, id=$newId');
      } on PostgrestException catch (pe) {
        _log('createTreasury RPC failed (${pe.code}): ${pe.message}');
        if (pe.code == 'PGRST202' && params.containsKey('p_company_id')) {
          final fallbackParams = Map<String, dynamic>.from(params)..remove('p_company_id');
          try {
            newId = await _client.rpc('create_treasury', params: fallbackParams);
            _log('createTreasury via fallback RPC: OK, id=$newId');
            if (companyId != null && newId != null) {
              await _client
                  .from('treasuries')
                  .update({'company_id': companyId})
                  .eq('id', newId);
            }
          } catch (pe2) {
            _log('createTreasury fallback RPC also failed: $pe2');
          }
        }
      }

      // Fallback to direct insert if RPC failed or is missing
      if (newId == null) {
        _log('createTreasury: Falling back to direct database insert');
        final insertData = <String, dynamic>{
          'name': name,
          'type': type,
          'approval_status': 'approved',
          'is_active': true,
        };
        if (employeeId != null) {
          insertData['employee_id'] = employeeId;
          insertData['user_id'] = employeeId;
        }
        if (notes != null && notes.isNotEmpty) {
          insertData['notes'] = notes;
        }
        if (companyId != null) {
          insertData['company_id'] = companyId;
        }

        final inserted = await _client
            .from('treasuries')
            .insert(insertData)
            .select('id')
            .single();
        newId = inserted['id'];

        // Initialize balances for the new treasury
        for (final curr in ['EGP', 'USD', 'EUR', 'GBP']) {
          await _client.from('treasury_balances').upsert({
            'treasury_id': newId,
            'currency': curr,
            'balance': 0.0,
          }, onConflict: 'treasury_id, currency');
        }
        _log('createTreasury via direct insert: OK, id=$newId');
      }

      // Ensure dedicated Level-5 account exists in COA for employee custody
      if (type == 'employee' || type == 'custody') {
        try {
          await ensureCustodyAccount('$newId');
        } catch (e) {
          _log('ensureCustodyAccount background call notice: $e');
        }
      }

      final fullResult = await _client
          .from('treasuries')
          .select('*, balances:treasury_balances(*)')
          .eq('id', newId)
          .single();

      return TreasuryModel.fromMap(
          Map<String, dynamic>.from(fullResult as Map));
    } catch (e) {
      _log('createTreasury error: $e');
      final errorStr = e.toString();
      if (errorStr.contains('23505') || errorStr.contains('name_unique')) {
        throw Exception('يوجد خزنة بهذا الاسم بالفعل، يرجى اختيار اسم مختلف');
      }
      rethrow;
    }
  }

  /// Ensures and provisions a dedicated Level-5 posting account for an employee custody.
  Future<int?> ensureCustodyAccount(String treasuryId) async {
    try {
      final res = await _client.rpc('ensure_custody_account', params: {
        'p_treasury_id': int.tryParse(treasuryId) ?? treasuryId,
        if (TenantService().tenantId != null) 'p_company_id': TenantService().tenantId,
      });
      _log('ensureCustodyAccount: accountId=$res for treasury=$treasuryId');
      if (res is int) return res;
      return int.tryParse('$res');
    } catch (e) {
      _log('ensureCustodyAccount error: $e');
      return null;
    }
  }

  /// Admin disburses funds from Main Treasury to an Employee Treasury.
  Future<void> createDisbursement({
    required String fromTreasuryId,
    required String toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    _log('createDisbursement: from=$fromTreasuryId to=$toTreasuryId cur=$currency amt=$amount desc=$description');
    try {
      await _client.rpc('disburse_custody', params: {
        'p_from_treasury_id': int.tryParse(fromTreasuryId) ?? fromTreasuryId,
        'p_to_treasury_id': int.tryParse(toTreasuryId) ?? toTreasuryId,
        'p_currency': currency,
        'p_amount': amount,
        'p_description': description,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      });
      _log('createDisbursement via RPC: OK');
    } catch (e) {
      _log('RPC disburse_custody failed, falling back: $e');
      final balRes = await _client
          .from('treasury_balances')
          .select('balance')
          .eq('treasury_id', fromTreasuryId)
          .eq('currency', currency)
          .maybeSingle();
      final currentBalance = (balRes?['balance'] as num?)?.toDouble() ?? 0.0;
      if (currentBalance < amount) {
        throw Exception('الرصيد غير كافٍ في الخزنة المصدرة (المتوفر: ${currentBalance.toStringAsFixed(2)})');
      }
      await _doAtomic([
        _updateBalance(fromTreasuryId, currency, -amount),
        _createTx(fromTreasuryId, 'disbursement_out', currency, amount, description,
            toTreasuryId,
            isDebit: true),
        _updateBalance(toTreasuryId, currency, amount),
        _createTx(toTreasuryId, 'disbursement', currency, amount,
            description, fromTreasuryId,
            isDebit: false),
      ]);
    }
  }

  /// Transfer from one employee treasury to another with optional Branch & Cost Center tracking.
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
    try {
      await _client.rpc('transfer_custody', params: {
        'p_from_treasury_id': int.tryParse(fromTreasuryId) ?? fromTreasuryId,
        'p_to_treasury_id': int.tryParse(toTreasuryId) ?? toTreasuryId,
        'p_currency': currency,
        'p_amount': amount,
        'p_description': description,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
        if (costCenterId != null && costCenterId.trim().isNotEmpty) 'p_cost_center_id': costCenterId.trim(),
        if (branchId != null) 'p_branch_id': int.tryParse(branchId.toString()) ?? branchId,
        if (toBranchId != null) 'p_to_branch_id': int.tryParse(toBranchId.toString()) ?? toBranchId,
        if (toCostCenterId != null && toCostCenterId.trim().isNotEmpty) 'p_to_cost_center_id': toCostCenterId.trim(),
      });
      _log('transferCustody via RPC: OK');
    } catch (e) {
      _log('RPC transfer_custody failed, falling back: $e');
      await _doAtomic([
        _updateBalance(fromTreasuryId, currency, -amount),
        _createTx(fromTreasuryId, 'transfer_out', currency, amount, description,
            toTreasuryId,
            isDebit: true),
        _updateBalance(toTreasuryId, currency, amount),
        _createTx(toTreasuryId, 'transfer_in', currency, amount, description,
            fromTreasuryId,
            isDebit: false),
      ]);
    }
  }

  /// Spend from own treasury (expense).
  Future<void> spend({
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
    debugPrint('═══════════════════════════════════════════════');
    debugPrint('💰 TREASURY_DAO.spend() ENTRY');
    debugPrint('  expenseAccountId = "$expenseAccountId" (${expenseAccountId.runtimeType})');
    debugPrint('  treasuryId       = "$treasuryId" (${treasuryId.runtimeType})');
    debugPrint('  currency         = "$currency"');
    debugPrint('  amount           = $amount');
    debugPrint('  supplierId       = "$supplierId"');
    debugPrint('  customerId       = "$customerId"');
    debugPrint('  shareholderId    = "$shareholderId"');
    debugPrint('═══════════════════════════════════════════════');

    // 1. Run validation
    SupplierSettlementService.instance.validateSupplierPayment(
      invoice: invoice,
      paymentAmount: amount,
    );

    // Validate expense account — required unless an entity is specified (auto-resolved in SQL)
    final hasEntity = supplierId != null || 
                      customerId != null || 
                      clearingAgentId != null || 
                      shippingCompanyId != null || 
                      shareholderId != null;
    if ((expenseAccountId == null || expenseAccountId.isEmpty) && !hasEntity) {
      debugPrint('❌ spend() BLOCKED: expenseAccountId is null/empty AND no entity is selected');
      throw Exception('يجب اختيار حساب مصروفات من شجرة الحسابات');
    }

    final parsedExpenseAccountId = expenseAccountId != null ? int.tryParse(expenseAccountId) : null;
    if (expenseAccountId != null && parsedExpenseAccountId == null) {
      debugPrint('❌ spend() BLOCKED: int.tryParse("$expenseAccountId") returned null');
      throw Exception('معرف حساب المصروفات غير صالح: "$expenseAccountId"');
    }

    debugPrint('✅ spend() parsedExpenseAccountId = $parsedExpenseAccountId (${parsedExpenseAccountId.runtimeType})');

    try {
      String? refType;
      String? refId;
      if (invoice != null) {
        if (invoice.notes == 'crop_lot' || invoice.id?.startsWith('lot_') == true) {
          refType = 'lot_receipt';
          refId = invoice.id?.replaceFirst('lot_', '') ?? invoice.purchaseNumber;
        } else {
          refType = 'purchase_invoice';
          refId = invoice.id?.toString() ?? invoice.purchaseNumber;
        }
      }

      final params = <String, dynamic>{
        'p_treasury_id': treasuryId,
        'p_currency': currency,
        'p_amount': amount,
        'p_description': description,
        if (parsedExpenseAccountId != null) 'p_expense_account_id': parsedExpenseAccountId,
        if (customerId != null) 'p_customer_id': customerId,
        if (supplierId != null) 'p_supplier_id': supplierId,
        if (clearingAgentId != null) 'p_clearing_agent_id': clearingAgentId,
        if (shippingCompanyId != null) 'p_shipping_company_id': shippingCompanyId,
        if (shareholderId != null) 'p_shareholder_id': shareholderId,
        if (refType != null) 'p_reference_type': refType,
        if (refId != null) 'p_reference_id': refId,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
        if (costCenterId != null && costCenterId.isNotEmpty) 'p_cost_center_id': costCenterId,
        if (branchId != null) 'p_branch_id': int.tryParse(branchId.toString()) ?? branchId,
      };

      debugPrint('💰 spend() → RPC CALLING spend_custody');
      debugPrint('💰 spend() → params = $params');
      debugPrint('💰 spend() → param types:');
      params.forEach((k, v) => debugPrint('   $k: $v (${v.runtimeType})'));

      final res = await _client.rpc('spend_custody', params: params);
      final int txId = res is Map
          ? ((res['transaction_id'] ?? res['id']) as num?)?.toInt() ?? 0
          : (res is num ? res.toInt() : int.tryParse(res?.toString() ?? '') ?? 0);
      _log('spend via RPC: OK (txId=$txId)');
    } catch (e) {
      _log('RPC spend_custody failed: $e');
      rethrow;
    } finally {
      if (invoice != null && invoice.id != null && invoice.notes != 'crop_lot' && !invoice.id!.startsWith('lot_')) {
        await PurchaseInvoiceService.recalculate(invoice.id!.toString());
      }
    }
  }

  /// Spend with expense category tracking.
  Future<void> spendWithCategory({
    required String treasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? ledgerDescription,
    required String categoryId,
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
    debugPrint('═══════════════════════════════════════════════');
    debugPrint('💰 TREASURY_DAO.spendWithCategory() ENTRY');
    debugPrint('  expenseAccountId = "$expenseAccountId" (${expenseAccountId.runtimeType})');
    debugPrint('  treasuryId       = "$treasuryId" (${treasuryId.runtimeType})');
    debugPrint('  currency         = "$currency"');
    debugPrint('  amount           = $amount');
    debugPrint('  categoryId       = "$categoryId"');
    debugPrint('  supplierId       = "$supplierId"');
    debugPrint('  customerId       = "$customerId"');
    debugPrint('  shareholderId    = "$shareholderId"');
    debugPrint('  costCenterId     = "$costCenterId"');
    debugPrint('  branchId         = "$branchId"');
    debugPrint('═══════════════════════════════════════════════');

    // 1. Run validation
    SupplierSettlementService.instance.validateSupplierPayment(
      invoice: invoice,
      paymentAmount: amount,
    );

    final parsedExpenseAccountId = expenseAccountId != null ? int.tryParse(expenseAccountId) : null;
    debugPrint('✅ spendWithCategory parsedExpenseAccountId = $parsedExpenseAccountId (${parsedExpenseAccountId.runtimeType})');

    try {
      String? refType;
      String? refId;
      if (invoice != null) {
        if (invoice.notes == 'crop_lot' || invoice.id?.startsWith('lot_') == true) {
          refType = 'lot_receipt';
          refId = invoice.id?.replaceFirst('lot_', '') ?? invoice.purchaseNumber;
        } else {
          refType = 'purchase_invoice';
          refId = invoice.id?.toString() ?? invoice.purchaseNumber;
        }
      }

      final params = <String, dynamic>{
        'p_treasury_id': treasuryId,
        'p_currency': currency,
        'p_amount': amount,
        'p_description': description,
        'p_category_id': (int.tryParse(categoryId) ?? 0) > 0 ? int.tryParse(categoryId) : null,
        if (parsedExpenseAccountId != null) 'p_expense_account_id': parsedExpenseAccountId,
        if (customerId != null) 'p_customer_id': customerId,
        if (supplierId != null) 'p_supplier_id': supplierId,
        if (clearingAgentId != null) 'p_clearing_agent_id': clearingAgentId,
        if (shippingCompanyId != null) 'p_shipping_company_id': shippingCompanyId,
        if (shareholderId != null) 'p_shareholder_id': shareholderId,
        if (refType != null) 'p_reference_type': refType,
        if (refId != null) 'p_reference_id': refId,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
        if (costCenterId != null && costCenterId.isNotEmpty) 'p_cost_center_id': costCenterId,
        if (branchId != null) 'p_branch_id': int.tryParse(branchId.toString()) ?? branchId,
      };

      debugPrint('💰 spendWithCategory → RPC CALLING spend_with_category');
      debugPrint('💰 spendWithCategory → params = $params');
      debugPrint('💰 spendWithCategory → param types:');
      params.forEach((k, v) => debugPrint('   $k: $v (${v.runtimeType})'));

      final res = await _client.rpc('spend_with_category', params: params);
      final int txId = res is Map
          ? ((res['transaction_id'] ?? res['id']) as num?)?.toInt() ?? 0
          : (res is num ? res.toInt() : int.tryParse(res?.toString() ?? '') ?? 0);
      _log('spendWithCategory via RPC: OK (txId=$txId, cat=$categoryId, acct=$expenseAccountId)');
    } catch (e) {
      _log('RPC spend_with_category failed: $e');
      rethrow;
    } finally {
      if (invoice != null && invoice.id != null && invoice.notes != 'crop_lot' && !invoice.id!.startsWith('lot_')) {
        await PurchaseInvoiceService.recalculate(invoice.id!.toString());
      }
    }
  }

  /// Exchange currency within the same treasury
  Future<void> exchangeCurrency({
    required String treasuryId,
    required String fromCurrency,
    required String toCurrency,
    required double amountFrom,
    required double amountTo,
    required double exchangeRate,
    String transferMode = 'exchange',
  }) async {
    try {
      final userResponse = await _client.auth.getUser();
      final userId = userResponse.user?.id;

      if (userId == null) throw Exception('المستخدم غير مسجل الدخول');

      await _client.rpc('exchange_currency', params: {
        'p_treasury_id': treasuryId,
        'p_from_currency': fromCurrency,
        'p_to_currency': toCurrency,
        'p_amount_from': amountFrom,
        'p_amount_to': amountTo,
        'p_exchange_rate': exchangeRate,
        'p_user_id': userId,
        'p_transfer_mode': transferMode,
      });
      _log('exchangeCurrency via RPC: OK');
    } catch (e) {
      _log('RPC exchange_currency failed: $e');
      throw Exception('فشل تحويل العملة: $e');
    }
  }

  /// Return from employee treasury to main treasury.
  Future<void> returnCustody({
    required String fromTreasuryId,
    required String toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    try {
      await _client.rpc('return_custody', params: {
        'p_from_treasury_id': int.tryParse(fromTreasuryId) ?? fromTreasuryId,
        'p_to_treasury_id': int.tryParse(toTreasuryId) ?? toTreasuryId,
        'p_currency': currency,
        'p_amount': amount,
        'p_description': description,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      });
      _log('returnCustody via RPC: OK');
    } catch (e) {
      _log('RPC return_custody failed, falling back: $e');
      final bal = await _getCurrentBalance(fromTreasuryId, currency);
      if (bal < amount) {
        throw Exception(
            'الرصيد غير كافٍ في $currency (المتوفر: ${bal.toStringAsFixed(2)})');
      }
      await _doAtomic([
        _updateBalance(fromTreasuryId, currency, -amount),
        _createTx(fromTreasuryId, 'return_out', currency, amount,
            description, toTreasuryId,
            isDebit: true),
        _updateBalance(toTreasuryId, currency, amount),
        _createTx(toTreasuryId, 'return_in', currency, amount,
            description, fromTreasuryId,
            isDebit: false),
      ]);
    }
  }

  // ── Deposit ──

  Future<void> deposit({
    required String treasuryId,
    required String currency,
    required double amount,
    String description = '',
    int? categoryId,
    int? revenueAccountId,
    String? notes,
  }) async {
    try {
      await _client.rpc('deposit_treasury', params: {
        'p_treasury_id': int.tryParse(treasuryId),
        'p_currency': currency,
        'p_amount': amount,
        'p_description': description,
        'p_revenue_account_id': revenueAccountId,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      });
      _log('deposit via RPC: OK');
    } catch (e) {
      _log('RPC deposit_treasury failed, falling back: $e');
      if (amount <= 0) {
        throw Exception('المبلغ يجب أن يكون أكبر من صفر');
      }
      await _doAtomic([
        _updateBalance(treasuryId, currency, amount),
        _createTx(
            treasuryId, 'deposit', currency, amount, description, null,
            isDebit: false, categoryId: categoryId?.toString()),
      ]);
    }
  }

  // ── Withdraw (Admin only) ──

  Future<void> withdraw({
    required String treasuryId,
    required String currency,
    required double amount,
    String description = '',
    int? categoryId,
    String? notes,
  }) async {
    try {
      await _client.rpc('withdraw_treasury', params: {
        'p_treasury_id': int.tryParse(treasuryId) ?? treasuryId,
        'p_currency': currency,
        'p_amount': amount,
        'p_description': description,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      });
      _log('withdraw via RPC: OK');
    } catch (e) {
      _log('RPC withdraw_treasury failed, falling back: $e');
      final bal = await _getCurrentBalance(treasuryId, currency);
      if (bal < amount) {
        throw Exception(
            'الرصيد غير كافٍ في $currency (المتوفر: ${bal.toStringAsFixed(2)})');
      }
      await _doAtomic([
        _updateBalance(treasuryId, currency, -amount),
        _createTx(treasuryId, 'withdrawal', currency, amount, description, null,
            isDebit: true, categoryId: categoryId?.toString()),
      ]);
    }
  }

  // ── Reverse Transaction (Admin only) ──

  Future<void> updateTransaction({
    required String transactionId,
    String? description,
    String? categoryId,
    double? amount,
    String? transactionType,
    String? treasuryId,
    String? currency,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (description != null) updates['description'] = description;
      if (categoryId != null) updates['category_id'] = categoryId;
      if (transactionType != null) updates['type'] = transactionType;
      if (treasuryId != null) updates['treasury_id'] = treasuryId;
      if (currency != null) updates['currency'] = currency;
      if (updates.isEmpty && amount == null) return;

      final tx = await _client
          .from('treasury_transactions')
          .select('treasury_id, currency, amount, type, customer_id, supplier_id, clearing_agent_id, shipping_company_id, journal_entry_id')
          .eq('id', transactionId)
          .maybeSingle();
      if (tx == null) throw Exception('الحركة غير موجودة');

      final oldTreasId = tx['treasury_id']?.toString() ?? '';
      final oldCurrency = tx['currency']?.toString() ?? 'EGP';
      final targetCurrency = currency ?? oldCurrency;
      final oldAmount = (tx['amount'] as num?)?.toDouble().abs() ?? 0.0;
      final oldTxType = tx['type']?.toString() ?? '';

      final absNew = amount ?? oldAmount;
      final newType = transactionType ?? oldTxType;

      const outflowTypes = {'expense', 'withdrawal', 'transfer_out', 'return_out', 'disbursement_out'};
      final oldIsOutflow = outflowTypes.contains(oldTxType);
      final newIsOutflow = outflowTypes.contains(newType);

      // Amount is always stored as positive
      if (amount != null) updates['amount'] = absNew;

      final targetTreasId = treasuryId ?? oldTreasId;

      // ── Treasury balance delta ──
      final oldTxDelta = oldIsOutflow ? -oldAmount : oldAmount;
      final newTxDelta = newIsOutflow ? -absNew : absNew;
      final treasuryDelta = newTxDelta - oldTxDelta;

      final batch = <Future<void>>[];
      if (targetCurrency == oldCurrency) {
        if (targetTreasId == oldTreasId) {
          if (treasuryDelta != 0) {
            batch.add(_updateBalance(targetTreasId, oldCurrency, treasuryDelta));
          }
        } else {
          batch.add(_updateBalance(oldTreasId, oldCurrency, -oldTxDelta));
          batch.add(_updateBalance(targetTreasId, oldCurrency, newTxDelta));
        }
      } else {
        // Currency changed: reverse from old currency, add to new currency
        batch.add(_updateBalance(oldTreasId, oldCurrency, -oldTxDelta));
        batch.add(_updateBalance(targetTreasId, targetCurrency, newTxDelta));
      }

      // ── Counterparty balance delta ──
      // Customer: outflow (expense) = balance goes UP (they owe us more)
      //           inflow (deposit)  = balance goes DOWN (they paid us)
      final oldCustomerEffect = oldIsOutflow ? oldAmount : -oldAmount;
      final newCustomerEffect = newIsOutflow ? absNew : -absNew;
      final customerDelta = newCustomerEffect - oldCustomerEffect;

      // Vendor: outflow (expense) = we owe them LESS → balance goes DOWN
      //         inflow (deposit)  = we owe them MORE → balance goes UP
      final oldVendorEffect = oldIsOutflow ? -oldAmount : oldAmount;
      final newVendorEffect = newIsOutflow ? -absNew : absNew;
      final vendorDelta = newVendorEffect - oldVendorEffect;

      final customerId = tx['customer_id'] is int
          ? tx['customer_id'] as int
          : int.tryParse(tx['customer_id']?.toString() ?? '');
      final supplierId = tx['supplier_id']?.toString();
      final clearingAgentId = tx['clearing_agent_id'] is int
          ? tx['clearing_agent_id'] as int
          : int.tryParse(tx['clearing_agent_id']?.toString() ?? '');
      final shippingCompanyId = tx['shipping_company_id'] is int
          ? tx['shipping_company_id'] as int
          : int.tryParse(tx['shipping_company_id']?.toString() ?? '');

      final needsLedgerUpdate = amount != null && (customerId != null || supplierId != null || clearingAgentId != null || shippingCompanyId != null);

      // 1) RPC: ONLY update ledger_entries (audit trail / computed balance)
      if (needsLedgerUpdate) {
        try {
          final entryType = newIsOutflow ? 'debit' : 'credit';
          await _client.rpc('update_treasury_ledger', params: {
            'p_reference_id': transactionId,
            'p_new_amount': absNew,
            'p_new_entry_type': entryType,
          });
        } catch (e) {
          _log('update_treasury_ledger RPC failed: $e');
        }
      }

      // 2) ALWAYS adjust counterparty balance from Dart using calculated delta (source of truth)
      if (customerDelta != 0 && customerId != null) {
        batch.add(_reverseCustomerBalance(customerId, customerDelta));
      }
      if (vendorDelta != 0) {
        if (supplierId != null) {
          batch.add(_reverseSupplierBalance(supplierId, vendorDelta));
        }
        if (clearingAgentId != null) {
          batch.add(_adjustVendorBalance('clearing_agent', clearingAgentId.toString(), vendorDelta));
        }
        if (shippingCompanyId != null) {
          batch.add(_adjustVendorBalance('shipping_company', shippingCompanyId.toString(), vendorDelta));
        }
      }

      // 3) Synchronize GL / Journal Entry if linked
      final jeId = tx['journal_entry_id'];
      if (jeId != null) {
        try {
          if (description != null && description.isNotEmpty) {
            await _client.from('journal_entries').update({
              'description': description,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', jeId);
          }

          if (amount != null) {
            final lines = await _client
                .from('account_ledger_entries')
                .select('id, debit, credit')
                .eq('journal_entry_id', jeId);

            for (final line in lines) {
              final lineId = line['id'];
              final oldDebit = (line['debit'] as num?)?.toDouble() ?? 0.0;
              final oldCredit = (line['credit'] as num?)?.toDouble() ?? 0.0;
              final lineUpdates = <String, dynamic>{};
              if (oldDebit > 0) {
                lineUpdates['debit'] = absNew;
                lineUpdates['amount_in_base_currency'] = absNew;
              } else if (oldCredit > 0) {
                lineUpdates['credit'] = absNew;
                lineUpdates['amount_in_base_currency'] = absNew;
              }
              if (description != null && description.isNotEmpty) {
                lineUpdates['description'] = description;
              }
              if (lineUpdates.isNotEmpty) {
                await _client.from('account_ledger_entries').update(lineUpdates).eq('id', lineId);
              }
            }
          }
        } catch (glError) {
          _log('Error syncing GL for journal_entry $jeId: $glError');
        }
      }

      if (batch.isNotEmpty) await _doAtomic(batch);

      // Update the transaction row itself
      final updatePayload = <String, dynamic>{};
      if (description != null) updatePayload['description'] = description;
      if (categoryId != null) {
        updatePayload['category_id'] = int.tryParse(categoryId) ?? categoryId;
      }
      if (updates.containsKey('amount')) updatePayload['amount'] = updates['amount'];
      if (transactionType != null) updatePayload['type'] = transactionType;
      if (treasuryId != null) {
        updatePayload['treasury_id'] = int.tryParse(treasuryId) ?? treasuryId;
      }
      if (currency != null) updatePayload['currency'] = targetCurrency;
      if (updatePayload.isNotEmpty) {
        await _client.from('treasury_transactions').update(updatePayload).eq('id', transactionId);
      }
      _log('updateTransaction($transactionId): OK');
    } catch (e) {
      _log('updateTransaction error: $e');
      rethrow;
    }
  }

  Future<void> deleteTransaction({required String transactionId}) async {
    try {
      final tx = await _client
          .from('treasury_transactions')
          .select('treasury_id, currency, amount, type, customer_id, supplier_id, clearing_agent_id, shipping_company_id')
          .eq('id', transactionId)
          .maybeSingle();
      if (tx == null) throw Exception('الحركة غير موجودة');

      final treasuryId = tx['treasury_id'];
      final currency = tx['currency']?.toString() ?? 'EGP';
      final amount = (tx['amount'] as num?)?.toDouble().abs() ?? 0.0;
      final txType = tx['type']?.toString() ?? '';
      final isOutflow = {'expense', 'withdrawal', 'transfer_out', 'return_out', 'disbursement_out'}.contains(txType);
      final customerId = tx['customer_id'] is int
          ? tx['customer_id'] as int
          : int.tryParse(tx['customer_id']?.toString() ?? '');
      final supplierId = tx['supplier_id']?.toString();
      final clearingAgentId = tx['clearing_agent_id'] is int
          ? tx['clearing_agent_id'] as int
          : int.tryParse(tx['clearing_agent_id']?.toString() ?? '');
      final shippingCompanyId = tx['shipping_company_id'] is int
          ? tx['shipping_company_id'] as int
          : int.tryParse(tx['shipping_company_id']?.toString() ?? '');

      // 1) RPC: ONLY delete ledger_entries (cleanup audit trail)
      try {
        await _client.rpc('delete_treasury_ledger', params: {
          'p_reference_id': transactionId,
        });
      } catch (e) {
        _log('delete_treasury_ledger RPC failed (ledger cleanup): $e');
      }

      // 2) Delete the transaction row
      await _client.from('treasury_transactions').delete().eq('id', transactionId);

      // 3) Recalculate treasury balance from remaining transactions
      final remaining = await _client
          .from('treasury_transactions')
          .select('amount, type')
          .eq('treasury_id', treasuryId)
          .eq('currency', currency);

      double totalBalance = 0;
      for (final row in remaining) {
        final amt = (row['amount'] as num?)?.toDouble() ?? 0;
        final rowType = row['type'] as String? ?? '';
        final rowIsOutflow = {'expense', 'withdrawal', 'transfer_out', 'return_out', 'disbursement_out'}.contains(rowType);
        totalBalance += rowIsOutflow ? -amt : amt;
      }

      final existing = await _client
          .from('treasury_balances')
          .select('id')
          .eq('treasury_id', treasuryId)
          .eq('currency', currency)
          .maybeSingle();

      if (existing != null) {
        await _client
            .from('treasury_balances')
            .update({'balance': totalBalance}).eq('id', existing['id']);
      }

      // 4) ALWAYS reverse counterparty from Dart using treasury_transactions amount (source of truth)
      // Customer: outflow = balance went UP → to reverse, go DOWN
      //           inflow = balance went DOWN → to reverse, go UP
      if (customerId != null) {
        final reverseDelta = isOutflow ? -amount : amount;
        await _reverseCustomerBalance(customerId, reverseDelta);
      }
      // Vendor: outflow = balance went DOWN → to reverse, go UP
      //         inflow = balance went UP → to reverse, go DOWN
      if (supplierId != null) {
        final reverseDelta = isOutflow ? amount : -amount;
        await _reverseSupplierBalance(supplierId, reverseDelta);
      }
      if (clearingAgentId != null) {
        final reverseDelta = isOutflow ? amount : -amount;
        await _adjustVendorBalance('clearing_agent', clearingAgentId.toString(), reverseDelta);
      }
      if (shippingCompanyId != null) {
        final reverseDelta = isOutflow ? amount : -amount;
        await _adjustVendorBalance('shipping_company', shippingCompanyId.toString(), reverseDelta);
      }

      _log('deleteTransaction($transactionId): OK');
    } catch (e) {
      _log('deleteTransaction error: $e');
      rethrow;
    }
  }

  // ── Ledger Queries ──

  Future<List<Map<String, dynamic>>> getLedgerEntries({
    required String entityType,
    required String entityId,
  }) async {
    try {
      final data = await _client
          .from('ledger_entries')
          .select()
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .order('created_at', ascending: true)
          .limit(1000);
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _log('getLedgerEntries error: $e');
      rethrow;
    }
  }

  /// Fetch transactions with full relations for export (no pagination).


  /// Fetch customer map {id -> name} for export enrichment.
  Future<Map<String, String>> getCustomerNameMap() async {
    try {
      final data = await _client
          .from('customers')
          .select('id, name');
      return {for (final r in data) '${r['id']}': '${r['name']}'};
    } catch (_) {
      return {};
    }
  }

  // Fetch supplier map {id -> name} for export enrichment.
  Future<Map<String, String>> getSupplierNameMap() async {
    try {
      final data = await _client
          .from('suppliers')
          .select('id, name');
      return {for (final r in data) '${r['id']}': '${r['name']}'};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> getClearingAgentNameMap() async {
    try {
      final data = await _client
          .from('clearing_agents')
          .select('id, name');
      return {for (final r in data) '${r['id']}': '${r['name']}'};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> getShippingCompanyNameMap() async {
    try {
      final data = await _client
          .from('shipping_companies')
          .select('id, name');
      return {for (final r in data) '${r['id']}': '${r['name']}'};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> getShareholderNameMap() async {
    try {
      final data = await _client
          .from('shareholders')
          .select('id, name');
      return {for (final r in data) '${r['id']}': '${r['name']}'};
    } catch (_) {
      return {};
    }
  }

  // ── Helpers ──

  Future<bool> isCurrentUserAdmin() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final data = await _client
          .from('users')
          .select('is_admin')
          .eq('id', userId)
          .maybeSingle();
      return data?['is_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<UserModel?> getCurrentUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final data = await _client
          .from('users')
          .select('id, full_name, email, is_admin')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return UserModel(
        id: data['id']?.toString(),
        email: data['email']?.toString(),
        fullName: data['full_name']?.toString(),
        isAdmin: data['is_admin'] == true,
        createdAt:
            data['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    final data = await _client
        .from('users')
        .select()
        .order('full_name', ascending: true);
    return (data as List).map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return UserModel(
        id: map['id']?.toString(),
        email: map['email']?.toString(),
        fullName: map['full_name']?.toString(),
        isAdmin: map['is_admin'] == true,
        createdAt:
            map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getEmployeeList() async {
    final data = await _client
        .from('users')
        .select('id, full_name')
        .eq('is_admin', false)
        .order('full_name');
    return (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Fetches comprehensive custody/treasury balance details reconciling:
  /// 1. Operational cash balance from `treasury_balances` (for specified currency, default EGP).
  /// 2. Chart of accounts mapping from `treasuries.account_id` or `treasury_balances.account_id` or `resolve_treasury_account`.
  /// 3. General Ledger movements from `account_ledger_entries` (sum of debit & credit).
  Future<Map<String, dynamic>> getCustodyBalanceDetails({
    required dynamic treasuryId,
    String currency = 'EGP',
  }) async {
    final tId = treasuryId.toString();
    try {
      final tData = await _client
          .from('treasuries')
          .select('id, name, type, employee_id, account_id, treasury_balances(id, balance, currency, account_id)')
          .eq('id', tId)
          .maybeSingle();

      double opBalance = 0.0;
      dynamic resolvedAccountId = tData?['account_id'];

      final balancesRaw = tData?['treasury_balances'];
      if (balancesRaw is List) {
        final match = balancesRaw.firstWhere(
          (b) => (b['currency']?.toString() ?? '').toUpperCase() == currency.toUpperCase(),
          orElse: () => null,
        );
        if (match != null) {
          opBalance = (match['balance'] as num?)?.toDouble() ?? 0.0;
          if (resolvedAccountId == null && match['account_id'] != null) {
            resolvedAccountId = match['account_id'];
          }
        }
      }

      if (opBalance == 0.0) {
        try {
          final directTb = await _client
              .from('treasury_balances')
              .select('balance, account_id')
              .eq('treasury_id', tId)
              .eq('currency', currency)
              .maybeSingle();
          if (directTb != null) {
            opBalance = (directTb['balance'] as num?)?.toDouble() ?? 0.0;
            if (resolvedAccountId == null && directTb['account_id'] != null) {
              resolvedAccountId = directTb['account_id'];
            }
          }
        } catch (_) {}
      }

      if (resolvedAccountId == null) {
        try {
          final rpcRes = await _client.rpc('resolve_treasury_account', params: {
            'p_treasury_id': int.tryParse(tId) ?? treasuryId,
            'p_currency': currency,
          });
          if (rpcRes != null) resolvedAccountId = rpcRes;
        } catch (_) {}
      }

      String? accountCode;
      String? accountName;
      double glDebit = 0.0;
      double glCredit = 0.0;
      double glNet = 0.0;

      if (resolvedAccountId != null) {
        try {
          final accRes = await _client
              .from('accounts')
              .select('id, account_code, name, account_name')
              .eq('id', resolvedAccountId)
              .maybeSingle();
          if (accRes != null) {
            accountCode = accRes['account_code']?.toString();
            accountName = accRes['account_name']?.toString() ?? accRes['name']?.toString();
          }

          final ales = await _client
              .from('account_ledger_entries')
              .select('debit, credit')
              .eq('account_id', resolvedAccountId);
          if (ales is List) {
            for (final e in ales) {
              glDebit += (e['debit'] as num?)?.toDouble() ?? 0.0;
              glCredit += (e['credit'] as num?)?.toDouble() ?? 0.0;
            }
            glNet = glDebit - glCredit;
          }
        } catch (_) {}
      }

      // Operational cash balance is primary for spending; fallback to ledger net if opBalance is 0
      final effectiveBalance = opBalance > 0.0 ? opBalance : (glNet > 0.0 ? glNet : opBalance);

      return {
        'custody_id': treasuryId,
        'custody_name': tData?['name']?.toString() ?? '',
        'balance': effectiveBalance,
        'operational_balance': opBalance,
        'gl_debit': glDebit,
        'gl_credit': glCredit,
        'gl_net': glNet,
        'account_id': resolvedAccountId,
        'account_code': accountCode,
        'account_name': accountName,
        'currency': currency,
      };
    } catch (e) {
      debugPrint('⚠️ TreasuryDao.getCustodyBalanceDetails error: $e');
      return {
        'custody_id': treasuryId,
        'balance': 0.0,
        'operational_balance': 0.0,
        'currency': currency,
      };
    }
  }

  Future<double> _getCurrentBalance(String treasuryId, String currency) async {
    final data = await _client
        .from('treasury_balances')
        .select('balance')
        .eq('treasury_id', treasuryId)
        .eq('currency', currency)
        .maybeSingle();
    if (data == null) return 0.0;
    return ((data['balance'] as num?)?.toDouble() ?? 0.0);
  }

  Future<void> _updateBalance(
      String treasuryId, String currency, double delta) async {
    final parsedTreasuryId = int.tryParse(treasuryId) ?? treasuryId;
    final existing = await _client
        .from('treasury_balances')
        .select('id, balance')
        .eq('treasury_id', parsedTreasuryId)
        .eq('currency', currency)
        .maybeSingle();

    if (existing != null) {
      final current = (existing['balance'] as num?)?.toDouble() ?? 0.0;
      final newBal = current + delta;
      if (newBal < 0) {
        throw Exception('الرصيد غير كافٍ في $currency (المتوفر: ${current.toStringAsFixed(2)})');
      }
      await _client
          .from('treasury_balances')
          .update({'balance': newBal}).eq('id', existing['id']);
    } else {
      if (delta < 0) {
        throw Exception('الرصيد غير كافٍ في $currency (المتوفر: 0.00)');
      }
      await _client.from('treasury_balances').insert({
        'treasury_id': parsedTreasuryId,
        'currency': currency,
        'balance': delta,
      });
    }
  }

  Future<int> _createTx(
    String treasuryId,
    String type,
    String currency,
    double amount,
    String description,
    String? relatedTreasuryId, {
    bool isDebit = false,
    String? categoryId,
    String? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
  }) async {
    assert(type.isNotEmpty, '_createTx: type must not be empty');
    assert(amount >= 0, '_createTx: amount must be non-negative');

    final currentBal = await _getCurrentBalance(treasuryId, currency);
    final balanceAfter = currentBal;
    final balanceBefore = isDebit ? currentBal + amount : (currentBal - amount < 0 ? 0.0 : currentBal - amount);

    final response = await _client.from('treasury_transactions').insert({
      'treasury_id': treasuryId,
      'type': type,
      'currency': currency,
      'amount': amount,
      'balance_before': balanceBefore,
      'balance_after': balanceAfter,
      'description': description,
      if (relatedTreasuryId != null) 'related_treasury_id': relatedTreasuryId,
      if (categoryId != null) 'category_id': categoryId,
      if (customerId != null) 'customer_id': customerId,
      if (supplierId != null) 'supplier_id': supplierId,
      if (clearingAgentId != null) 'clearing_agent_id': clearingAgentId,
      if (shippingCompanyId != null) 'shipping_company_id': shippingCompanyId,
      if (shareholderId != null) 'shareholder_id': shareholderId,
      'created_by': _client.auth.currentUser?.id,
      'currency_snapshot': (await CurrencyConversionService.instance.createSnapshotFromDb(
        currency: currency,
        amount: amount,
      )).toJson(),
    }).select('id').single();

    final txId = response['id'] as int;

    await FinancialAuditLogDao().logInsert(
      tableName: 'treasury_transactions',
      recordId: txId.toString(),
      snapshot: {
        'treasury_id': treasuryId,
        'type': type,
        'currency': currency,
        'amount': amount,
        'description': description,
        if (relatedTreasuryId != null) 'related_treasury_id': relatedTreasuryId,
        'created_by': _client.auth.currentUser?.id,
      },
      reason: 'Treasury transaction created: $type $currency $amount',
    );

    return txId;
  }

  Future<void> _reverseCustomerBalance(int customerId, double amount) async {
    final customer = await _client
        .from('customers')
        .select('balance')
        .eq('id', customerId)
        .maybeSingle();
      if (customer != null) {
        final current = (customer['balance'] as num?)?.toDouble() ?? 0.0;
        await _client.from('customers').update({'balance': current + amount}).eq('id', customerId).eq('company_id', TenantService().tenantId!);
      }
  }

  Future<void> _reverseSupplierBalance(String supplierId, double amount) async {
    final supplier = await _client
        .from('suppliers')
        .select('outstanding_balance')
        .eq('id', supplierId)
        .maybeSingle();
      if (supplier != null) {
        final current = (supplier['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
        await _client.from('suppliers').update({'outstanding_balance': current + amount}).eq('id', supplierId).eq('company_id', TenantService().tenantId!);
      }
  }

  Future<void> _adjustVendorBalance(String vendorType, String vendorId, double delta) async {
    switch (vendorType) {
      case 'clearing_agent':
        final agent = await _client
            .from('clearing_agents')
            .select('manual_adjustment, balance')
            .eq('id', int.parse(vendorId))
            .maybeSingle();
        if (agent == null) return;
        final curAdj = (agent['manual_adjustment'] as num?)?.toDouble() ?? 0.0;
        final curBal = (agent['balance'] as num?)?.toDouble() ?? 0.0;
        await _client.from('clearing_agents').update({
          'manual_adjustment': curAdj + delta,
          'balance': curBal + delta,
        }).eq('id', int.parse(vendorId));
      case 'shipping_company':
        final comp = await _client
            .from('shipping_companies')
            .select('manual_adjustment, balance')
            .eq('id', int.parse(vendorId))
            .maybeSingle();
        if (comp == null) return;
        final curAdj2 = (comp['manual_adjustment'] as num?)?.toDouble() ?? 0.0;
        final curBal2 = (comp['balance'] as num?)?.toDouble() ?? 0.0;
        await _client.from('shipping_companies').update({
          'manual_adjustment': curAdj2 + delta,
          'balance': curBal2 + delta,
        }).eq('id', int.parse(vendorId));
    }
  }

  Future<void> _adjustVendorForExpense(
    int txId,
    double amount,
    String currency,
    String desc, {
    int? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
  }) async {
    String? entityType;
    String? entityId;

    if (customerId != null) {
      entityType = 'customer';
      entityId = customerId.toString();
    } else if (supplierId != null) {
      entityType = 'supplier';
      entityId = supplierId;
    } else if (clearingAgentId != null) {
      entityType = 'clearing_agent';
      entityId = clearingAgentId.toString();
    } else if (shippingCompanyId != null) {
      entityType = 'shipping_company';
      entityId = shippingCompanyId.toString();
    } else if (shareholderId != null) {
      entityType = 'shareholder';
      entityId = shareholderId;
    }

    if (entityType == null || entityId == null) return;

    await _client.rpc('rpc_build_expense_subledger', params: {
      'payload': {
        'entity_type': entityType,
        'entity_id': entityId,
        'amount': amount,
        'currency': currency,
        'reference_type': 'expense',
        'reference_id': txId,
        'description': desc,
        'idempotency_key': 'exp_${txId}_$entityType',
      }
    });
  }

  /// Creates balanced GL entry for a supplier payment.
  ///
  /// Resolves the credit account dynamically from the treasury's GL mapping
  /// (treasury_balances.account_id). The debit account is 2120 (advance) or
  /// 2000 (invoice) depending on whether an invoice is selected.
  ///
  /// If no GL account mapping exists for the treasury, the GL entry is
  /// skipped with a warning log. The payment transaction is NOT rolled back.
  Future<void> _createSupplierGlEntry({
    required String treasuryId,
    required String currency,
    required PurchaseModel? invoice,
    required double amount,
    required String description,
    String? supplierId,
  }) async {
    try {
      final bool isAdvance = invoice == null;

      // 1. Resolve credit account from treasury GL mapping
      final creditAccountId =
          await TreasuryAccountResolver().getAccountId(treasuryId, currency);
      if (creditAccountId == null) {
        _log('GL entry skipped: Missing Chart of Accounts mapping for Treasury ID: $treasuryId');
        return;
      }

      // 2. Resolve debit account: use supplier's leaf account when available
      int? debitAccountId;
      String debitAccountCode = isAdvance ? '2120' : '2000';

      if (!isAdvance && supplierId != null) {
        // Look up supplier's individual leaf account (e.g., 20001)
        final supplierResponse = await _client
            .from('suppliers')
            .select('account_id')
            .eq('id', supplierId)
            .maybeSingle();
        final supplierAccountId = supplierResponse?['account_id'] as int?;
        if (supplierAccountId != null) {
          debitAccountId = supplierAccountId;
          debitAccountCode = 'supplier:$supplierAccountId';
          debugPrint('💰 _createSupplierGlEntry: using supplier leaf account $supplierAccountId');
        }
      }

      // Fallback: use parent account code
      if (debitAccountId == null) {
        debitAccountCode = isAdvance ? '2120' : '2000';
        debitAccountId =
            await ChartOfAccountsService().getAccountId(debitAccountCode);
      }

      if (debitAccountId == null) {
        _log('GL entry skipped: Account $debitAccountCode not found');
        return;
      }

      // 3. Build currency snapshot
      final snapshot =
          (await CurrencyConversionService.instance.createSnapshotFromDb(
            currency: currency,
            amount: amount,
          ))
              .toJson();

      // 4. Create balanced GL entry via RPC
      final entryNumber = await TransactionDao().insertBalancedEntry(
        debitAccountId: debitAccountId.toString(),
        creditAccountId: creditAccountId.toString(),
        amount: amount,
        description: description,
        transactionDate: DateTime.now().toIso8601String().substring(0, 10),
        currencySnapshot: snapshot,
      );
      _log('GL entry created ($entryNumber): Dr.$debitAccountCode Cr.treasury($creditAccountId) $currency ${amount.toStringAsFixed(2)}');
    } catch (e) {
      _log('GL entry failed (non-fatal): $e');
    }
  }

  Future<void> _doAtomic(List<Future<dynamic>> operations) async {
    for (final op in operations) {
      await op;
    }
  }

  // ─── Draft Transactions Management ──────────────────────────────────────

  Future<int> saveDraft({
    required int treasuryId,
    required String type,
    required double amount,
    required String currency,
    String? description,
    String? notes,
    int? categoryId,
    int? expenseAccountId,
    int? revenueAccountId,
    int? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
    Map<String, dynamic>? payload,
    String? costCenterId,
    dynamic branchId,
    dynamic toBranchId,
    String? toCostCenterId,
  }) async {
    final combinedPayload = <String, dynamic>{
      if (payload != null) ...payload,
      if (costCenterId != null && costCenterId.isNotEmpty) 'cost_center_id': costCenterId,
      if (branchId != null) 'branch_id': branchId,
      if (toBranchId != null) 'to_branch_id': toBranchId,
      if (toCostCenterId != null && toCostCenterId.isNotEmpty) 'to_cost_center_id': toCostCenterId,
    };
    final res = await _client.rpc('rpc_save_treasury_draft', params: {
      'p_treasury_id': treasuryId,
      'p_type': type,
      'p_amount': amount,
      'p_currency': currency,
      if (description != null) 'p_description': description,
      if (notes != null) 'p_notes': notes,
      if (categoryId != null) 'p_category_id': categoryId,
      if (expenseAccountId != null) 'p_expense_account_id': expenseAccountId,
      if (revenueAccountId != null) 'p_revenue_account_id': revenueAccountId,
      if (customerId != null) 'p_customer_id': customerId,
      if (supplierId != null && supplierId.isNotEmpty) 'p_supplier_id': supplierId,
      if (clearingAgentId != null) 'p_clearing_agent_id': clearingAgentId,
      if (shippingCompanyId != null) 'p_shipping_company_id': shippingCompanyId,
      if (shareholderId != null && shareholderId.isNotEmpty) 'p_shareholder_id': shareholderId,
      if (combinedPayload.isNotEmpty) 'p_payload': combinedPayload,
      if (costCenterId != null && costCenterId.isNotEmpty) 'p_cost_center_id': costCenterId,
      if (branchId != null) 'p_branch_id': int.tryParse(branchId.toString()) ?? branchId,
      if (toBranchId != null) 'p_to_branch_id': int.tryParse(toBranchId.toString()) ?? toBranchId,
      if (toCostCenterId != null && toCostCenterId.isNotEmpty) 'p_to_cost_center_id': toCostCenterId,
    });
    return (res as num).toInt();
  }

  Future<void> updateDraft({
    required int transactionId,
    int? treasuryId,
    double? amount,
    String? currency,
    String? description,
    String? notes,
    int? categoryId,
    int? expenseAccountId,
    int? revenueAccountId,
    int? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
    Map<String, dynamic>? payload,
    String? costCenterId,
    dynamic branchId,
    dynamic toBranchId,
    String? toCostCenterId,
  }) async {
    final combinedPayload = payload != null ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    if (costCenterId != null && costCenterId.isNotEmpty) {
      combinedPayload['cost_center_id'] = costCenterId;
    }
    if (branchId != null) {
      combinedPayload['branch_id'] = branchId;
    }
    if (toBranchId != null) {
      combinedPayload['to_branch_id'] = toBranchId;
    }
    if (toCostCenterId != null && toCostCenterId.isNotEmpty) {
      combinedPayload['to_cost_center_id'] = toCostCenterId;
    }
    await _client.rpc('rpc_update_treasury_draft', params: {
      'p_transaction_id': transactionId,
      if (treasuryId != null) 'p_treasury_id': treasuryId,
      if (amount != null) 'p_amount': amount,
      if (currency != null) 'p_currency': currency,
      if (description != null) 'p_description': description,
      if (notes != null) 'p_notes': notes,
      if (categoryId != null) 'p_category_id': categoryId,
      if (expenseAccountId != null) 'p_expense_account_id': expenseAccountId,
      if (revenueAccountId != null) 'p_revenue_account_id': revenueAccountId,
      if (customerId != null) 'p_customer_id': customerId,
      if (supplierId != null && supplierId.isNotEmpty) 'p_supplier_id': supplierId,
      if (clearingAgentId != null) 'p_clearing_agent_id': clearingAgentId,
      if (shippingCompanyId != null) 'p_shipping_company_id': shippingCompanyId,
      if (shareholderId != null && shareholderId.isNotEmpty) 'p_shareholder_id': shareholderId,
      if (combinedPayload.isNotEmpty) 'p_payload': combinedPayload,
      if (costCenterId != null && costCenterId.isNotEmpty) 'p_cost_center_id': costCenterId,
      if (branchId != null) 'p_branch_id': int.tryParse(branchId.toString()) ?? branchId,
      if (toBranchId != null) 'p_to_branch_id': int.tryParse(toBranchId.toString()) ?? toBranchId,
      if (toCostCenterId != null && toCostCenterId.isNotEmpty) 'p_to_cost_center_id': toCostCenterId,
    });
  }

  Future<void> deleteDraft(int transactionId) async {
    await _client.rpc('rpc_delete_treasury_draft', params: {
      'p_transaction_id': transactionId,
    });
  }

  Future<Map<String, dynamic>> confirmDraft(int transactionId) async {
    final res = await _client.rpc('rpc_confirm_treasury_draft', params: {
      'p_transaction_id': transactionId,
    });
    return Map<String, dynamic>.from(res as Map);
  }
}
