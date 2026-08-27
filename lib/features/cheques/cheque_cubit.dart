import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, Supabase;
import '../../data/dao/cheque_dao.dart';
import '../../data/models/cheque_model.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../data/models/shareholder_model.dart';
import '../../core/utils.dart';
import 'cheque_state.dart';

class ChequeCubit extends Cubit<ChequeState> {
  final ChequeDao _dao = ChequeDao();
  final CustomerDao _customerDao = CustomerDao();
  final SupplierDao _supplierDao = SupplierDao();
  final ClearingAgentDao _clearingAgentDao = ClearingAgentDao();
  final ShippingCompanyDao _shippingCompanyDao = ShippingCompanyDao();
  final _client = Supabase.instance.client;

  final chequeNumberCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final customerSearchCtrl = TextEditingController();
  final supplierSearchCtrl = TextEditingController();
  final clearingAgentSearchCtrl = TextEditingController();
  final shippingCompanySearchCtrl = TextEditingController();

  int _customerSearchVersion = 0;
  int _supplierSearchVersion = 0;
  int _clearingAgentSearchVersion = 0;
  int _shippingCompanySearchVersion = 0;
  int _shareholderSearchVersion = 0;

  final shareholderSearchCtrl = TextEditingController();

  ChequeCubit() : super(const ChequeInitial()) {
    _init();
  }

  List<ChequeModel> _applyFilters(List<ChequeModel> list, ChequeLoaded current) {
    var result = list;
    // Name/number search
    if (current.searchQuery.isNotEmpty) {
      final lower = current.searchQuery.toLowerCase();
      result = result.where((c) {
        final name = (c.counterpartyName ?? '').toLowerCase();
        final num = c.chequeNumber.toLowerCase();
        return name.contains(lower) || num.contains(lower);
      }).toList();
    }
    // Date filter
    if (current.fromDate != null) {
      final from = current.fromDate!;
      result = result.where((c) {
        try {
          final d = DateTime.parse(c.dueDate);
          return !d.isBefore(from);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    if (current.toDate != null) {
      final to = current.toDate!;
      result = result.where((c) {
        try {
          final d = DateTime.parse(c.dueDate);
          return !d.isAfter(to);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    return result;
  }

  Future<void> _init() async {
    emit(const ChequeLoading());
    debugPrint('🧾 ChequeCubit._init started');
    try {
      final results = await _dao.getAll();
      debugPrint('🧾 ChequeCubit._init: ${results.length} cheques loaded');
      final pendingCount = await _dao.getPendingCount();
      debugPrint('🧾 ChequeCubit._init: $pendingCount pending cheques');
      if (isClosed) return;
      emit(ChequeLoaded(
        cheques: results,
        hasMore: results.length >= 100,
        pendingCount: pendingCount,
      ));
    } catch (e, st) {
      debugPrint('🧾 ChequeCubit._init ERROR: $e\n$st');
      if (!isClosed) emit(ChequeError(message: 'حدث خطأ: $e'));
    }
  }

  Future<void> loadCheques({bool reset = false}) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    if (!reset && !current.hasMore) return;
    debugPrint('🧾 loadCheques(reset=$reset) offset=${reset ? 0 : current.cheques.length}');

    final offset = reset ? 0 : current.cheques.length;
    try {
      final results = await _dao.getAll(
        offset: offset,
        typeFilter: current.typeFilter,
        statusFilter: current.statusFilter,
      );
      debugPrint('🧾 loadCheques: ${results.length} results');
      final filtered = _applyFilters(results, current);
      emit(current.copyWith(
        cheques: reset ? filtered : [...current.cheques, ...filtered],
        hasMore: results.length >= 100,
      ));
    } catch (e, st) {
      debugPrint('🧾 loadCheques ERROR: $e\n$st');
      emit(current.copyWith());
    }
  }

  Future<void> loadPendingCount() async {
    final current = state;
    if (current is! ChequeLoaded) return;
    try {
      final count = await _dao.getPendingCount();
      emit(current.copyWith(pendingCount: count));
    } catch (e) {
      debugPrint('🧾 loadPendingCount ERROR: $e');
    }
  }

  void setTypeFilter(String? type) {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(typeFilter: type, clearTypeFilter: type == null));
    _reloadAll();
  }

  void setStatusFilter(String? status) {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(statusFilter: status, clearStatusFilter: status == null));
    _reloadAll();
  }

  void setSearchQuery(String q) {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(searchQuery: q));
    _reloadAll();
  }

  void setFromDate(DateTime? date) {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(fromDate: date, clearFromDate: date == null));
    _reloadAll();
  }

  void setToDate(DateTime? date) {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(toDate: date, clearToDate: date == null));
    _reloadAll();
  }

  void clearAllFilters() {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(
      clearTypeFilter: true,
      clearStatusFilter: true,
      clearFromDate: true,
      clearToDate: true,
      searchQuery: '',
    ));
    _reloadAll();
  }

  Future<void> _reloadAll() async {
    final current = state;
    if (current is! ChequeLoaded) return;
    try {
      final all = <ChequeModel>[];
      var offset = 0;
      while (true) {
        final batch = await _dao.getAll(
          offset: offset,
          limit: 500,
          typeFilter: current.typeFilter,
          statusFilter: current.statusFilter,
        );
        all.addAll(batch);
        if (batch.length < 500) break;
        offset += 500;
      }
      final filtered = _applyFilters(all, current);
      emit(current.copyWith(
        cheques: filtered,
        hasMore: false,
      ));
    } catch (e) {
      debugPrint('🧾 _reloadAll ERROR: $e');
    }
  }

  Future<void> searchCustomers(String q) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    if (q.trim().isEmpty) {
      emit(current.copyWith(customerResults: [], isLoadingCustomers: false));
      return;
    }
    final version = ++_customerSearchVersion;
    emit(current.copyWith(isLoadingCustomers: true));
    try {
      final results = await _customerDao.search(q.trim(), limit: 20);
      if (version != _customerSearchVersion) return;
      emit(current.copyWith(customerResults: results, isLoadingCustomers: false));
    } catch (_) {
      if (version != _customerSearchVersion) return;
      emit(current.copyWith(isLoadingCustomers: false));
    }
  }

  Future<void> searchSuppliers(String q) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    if (q.trim().isEmpty) {
      emit(current.copyWith(supplierResults: [], isLoadingSuppliers: false));
      return;
    }
    final version = ++_supplierSearchVersion;
    emit(current.copyWith(isLoadingSuppliers: true));
    try {
      final results = await _supplierDao.search(q.trim(), limit: 20);
      if (version != _supplierSearchVersion) return;
      emit(current.copyWith(supplierResults: results, isLoadingSuppliers: false));
    } catch (_) {
      if (version != _supplierSearchVersion) return;
      emit(current.copyWith(isLoadingSuppliers: false));
    }
  }

  Future<void> searchClearingAgents(String q) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    if (q.trim().isEmpty) {
      emit(current.copyWith(clearingAgentResults: [], isLoadingClearingAgents: false));
      return;
    }
    final version = ++_clearingAgentSearchVersion;
    emit(current.copyWith(isLoadingClearingAgents: true));
    try {
      final results = await _clearingAgentDao.search(q.trim(), limit: 20);
      if (version != _clearingAgentSearchVersion) return;
      emit(current.copyWith(clearingAgentResults: results, isLoadingClearingAgents: false));
    } catch (_) {
      if (version != _clearingAgentSearchVersion) return;
      emit(current.copyWith(isLoadingClearingAgents: false));
    }
  }

  Future<void> searchShippingCompanies(String q) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    if (q.trim().isEmpty) {
      emit(current.copyWith(shippingCompanyResults: [], isLoadingShippingCompanies: false));
      return;
    }
    final version = ++_shippingCompanySearchVersion;
    emit(current.copyWith(isLoadingShippingCompanies: true));
    try {
      final results = await _shippingCompanyDao.search(q.trim(), limit: 20);
      if (version != _shippingCompanySearchVersion) return;
      emit(current.copyWith(shippingCompanyResults: results, isLoadingShippingCompanies: false));
    } catch (_) {
      if (version != _shippingCompanySearchVersion) return;
      emit(current.copyWith(isLoadingShippingCompanies: false));
    }
  }

  Future<void> searchShareholders(String q) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    if (q.trim().isEmpty) {
      emit(current.copyWith(shareholderResults: [], isLoadingShareholders: false));
      return;
    }
    final version = ++_shareholderSearchVersion;
    emit(current.copyWith(isLoadingShareholders: true));
    try {
      final results = await ShareholderDao().search(q.trim(), limit: 20);
      if (version != _shareholderSearchVersion) return;
      emit(current.copyWith(shareholderResults: results, isLoadingShareholders: false));
    } catch (_) {
      if (version != _shareholderSearchVersion) return;
      emit(current.copyWith(isLoadingShareholders: false));
    }
  }

  Future<int?> saveCheque({
    required String type,
    required String currency,
    required String issueDate,
    required String dueDate,
    String? counterpartyType,
    int? counterpartyId,
    String? supplierId,
    String? shareholderId,
    int? clearingAgentId,
    int? shippingCompanyId,
    int? categoryId,
    int? expenseAccountId,
    int? treasuryId,
  }) async {
    final current = state;
    if (current is! ChequeLoaded) return null;

    if (chequeNumberCtrl.text.trim().isEmpty) {
      throw Exception('رقم الشيك مطلوب');
    }
    final exists = await _dao.chequeNumberExists(chequeNumberCtrl.text.trim());
    if (exists) {
      throw Exception('رقم الشيك موجود بالفعل');
    }
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    }

    // Validation: expense and account types require expense_account_id
    if ((counterpartyType == 'expense' || counterpartyType == 'account') && expenseAccountId == null) {
      throw Exception('يجب اختيار حساب محاسبي من شجرة الحسابات');
    }

    emit(current.copyWith(isSaving: true));
    try {
      final id = await _dao.create(
        chequeNumber: chequeNumberCtrl.text.trim(),
        type: type,
        amount: amount,
        currency: currency,
        issueDate: issueDate,
        dueDate: dueDate,
        counterpartyType: counterpartyType,
        counterpartyId: counterpartyId,
        supplierId: supplierId,
        shareholderId: shareholderId,
        clearingAgentId: clearingAgentId,
        shippingCompanyId: shippingCompanyId,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        categoryId: categoryId,
        expenseAccountId: expenseAccountId,
        treasuryId: treasuryId,
      );
      emit(current.copyWith(isSaving: false));
      clearForm();
      await loadCheques(reset: true);
      await loadPendingCount();
      return id;
    } catch (e) {
      emit(current.copyWith(isSaving: false));
      rethrow;
    }
  }

  Future<void> clearCheque(int id) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(isSaving: true));
    try {
      final cheque = await _dao.getById(id);

      if (cheque != null && cheque.counterpartyType == 'treasury') {
        final isOut = cheque.type == 'outgoing';
        final directionLabel = isOut ? 'صادر' : 'وارد';
        final now = DateTime.now().toIso8601String();

        // 1. Find bank account matching cheque currency
        final bankAccounts = await _client
            .from('bank_accounts')
            .select()
            .eq('currency', cheque.currency)
            .limit(1);
        if (bankAccounts.isEmpty) {
          throw Exception('لا يوجد حساب بنكي بالعملة ${cheque.currency}');
        }
        final bankAccount = bankAccounts.first;
        final bankId = bankAccount['id'] as int;

        // 2. Find treasury — use stored treasury_id or fallback to main
        String targetTreasuryId;
        String treasuryName;
        if (cheque.treasuryId != null) {
          targetTreasuryId = cheque.treasuryId.toString();
          final treasuryData = await _client
              .from('treasuries')
              .select('name')
              .eq('id', cheque.treasuryId!)
              .maybeSingle();
          treasuryName = treasuryData?['name']?.toString() ?? 'خزينة';
        } else {
          final treasuries = await _client
              .from('treasuries')
              .select('id, name')
              .eq('type', 'main')
              .limit(1);
          if (treasuries.isEmpty) {
            throw Exception('لا توجد خزينة رئيسية');
          }
          targetTreasuryId = treasuries.first['id'].toString();
          treasuryName = treasuries.first['name']?.toString() ?? 'الخزينة الرئيسية';
        }

        final desc = 'شيك $directionLabel رقم ${cheque.chequeNumber} - $treasuryName';
        final treasuryDao = TreasuryDao();

        if (isOut) {
          if ((bankAccount['balance'] as num).toDouble() < cheque.amount) {
            throw Exception('المبلغ المطلوب أكبر من المتوفر في الحساب البنكي');
          }
          // Outgoing: bank withdraw → treasury deposit
          await _client.rpc('withdraw_bank_account', params: {
            'p_account_id': bankId,
            'p_amount': cheque.amount,
            'p_description': desc,
            'p_entity_type': 'cheque',
            'p_entity_id': id.toString(),
            'p_counterparty_name': treasuryName,
          });
          await treasuryDao.deposit(
            treasuryId: targetTreasuryId,
            currency: cheque.currency,
            amount: cheque.amount,
            description: desc,
            categoryId: cheque.categoryId,
          );
        } else {
          // Incoming: treasury withdraw → bank deposit
          await treasuryDao.withdraw(
            treasuryId: targetTreasuryId,
            currency: cheque.currency,
            amount: cheque.amount,
            description: desc,
            categoryId: cheque.categoryId,
          );
          await _client.rpc('deposit_bank_account', params: {
            'p_account_id': bankId,
            'p_amount': cheque.amount,
            'p_description': desc,
            'p_entity_type': 'cheque',
            'p_entity_id': id.toString(),
            'p_counterparty_name': treasuryName,
          });
        }

        // 3. Update cheque status
        await _client.from('cheques').update({
          'status': 'cleared',
          'cleared_at': now,
        }).eq('id', id);
      } else {
        await _dao.clearCheque(id);
      }

      final now = DateTime.now().toIso8601String().substring(0, 10);
      final updated = current.cheques.map((c) {
        if (c.id == id.toString()) {
          return c.copyWith(status: 'cleared', clearedAt: now);
        }
        return c;
      }).toList();
      emit(current.copyWith(
        cheques: updated,
        isSaving: false,
        pendingCount: current.pendingCount - 1,
      ));
    } on PostgrestException catch (e) {
      debugPrint('🧾 clearCheque PostgrestException: ${e.message} | ${e.details} | ${e.hint}');
      emit(current.copyWith(isSaving: false));
      throw Exception('خطأ في قاعدة البيانات: ${e.message}');
    } catch (e) {
      emit(current.copyWith(isSaving: false));
      rethrow;
    }
  }

  Future<void> cancelCheque(int id) async {
    final current = state;
    if (current is! ChequeLoaded) return;
    emit(current.copyWith(isSaving: true));
    try {
      await _dao.cancelCheque(id);
      final now = DateTime.now().toIso8601String().substring(0, 10);
      final updated = current.cheques.map((c) {
        if (c.id == id.toString()) {
          return c.copyWith(status: 'cancelled', cancelledAt: now);
        }
        return c;
      }).toList();
      emit(current.copyWith(
        cheques: updated,
        isSaving: false,
        pendingCount: current.pendingCount - 1,
      ));
    } catch (e) {
      emit(current.copyWith(isSaving: false));
      rethrow;
    }
  }

  void clearForm() {
    chequeNumberCtrl.clear();
    amountCtrl.clear();
    notesCtrl.clear();
    customerSearchCtrl.clear();
    supplierSearchCtrl.clear();
    clearingAgentSearchCtrl.clear();
    shippingCompanySearchCtrl.clear();
  }

  Future<List<ChequeModel>> fetchAllFilteredCheques() async {
    final current = state;
    if (current is! ChequeLoaded) return [];
    try {
      final all = <ChequeModel>[];
      var offset = 0;
      while (true) {
        final batch = await _dao.getAll(
          offset: offset,
          limit: 500,
          typeFilter: current.typeFilter,
          statusFilter: current.statusFilter,
        );
        all.addAll(batch);
        if (batch.length < 500) break;
        offset += 500;
      }
      return _applyFilters(all, current);
    } catch (e) {
      debugPrint('🧾 fetchAllFilteredCheques ERROR: $e');
      return current.cheques;
    }
  }

  @override
  Future<void> close() {
    chequeNumberCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();
    customerSearchCtrl.dispose();
    supplierSearchCtrl.dispose();
    clearingAgentSearchCtrl.dispose();
    shippingCompanySearchCtrl.dispose();
    return super.close();
  }
}
