import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../../data/dao/account_dao.dart';
import '../../data/dao/cashbox_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/models/account_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../core/data_change_event_bus.dart';
import 'cash_receipt_state.dart';

class CashReceiptCubit extends Cubit<CashReceiptState> {
  final AccountDao _accountDao = AccountDao();
  final CustomerDao _customerDao = CustomerDao();
  final SupplierDao _supplierDao = SupplierDao();
  final CashboxDao _cashboxDao = CashboxDao();
  final TransactionDao _transactionDao = TransactionDao();
  final _client = Supabase.instance.client;

  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final customerCtrl = TextEditingController();
  final supplierCtrl = TextEditingController();
  final accountCtrl = TextEditingController();

  List<CustomerModel> get customerResults {
    final s = state;
    return s is CashReceiptLoaded ? s.customerResults : [];
  }

  List<SupplierModel> get supplierResults {
    final s = state;
    return s is CashReceiptLoaded ? s.supplierResults : [];
  }

  List<AccountModel> get accountResults {
    final s = state;
    return s is CashReceiptLoaded ? s.accountResults : [];
  }

  CashReceiptCubit() : super(const CashReceiptInitial()) {
    _init();
  }

  @override
  void emit(CashReceiptState state) {
    if (isClosed) return;
    super.emit(state);
  }

  Future<void> _init() async {
    final receiptNumber = await _generateReceiptNumber();
    emit(CashReceiptLoaded(
      receiptNumber: receiptNumber,
      transactionDate: DateTime.now(),
    ));
    await loadReceipts();
  }

  Future<String> _generateReceiptNumber() async {
    try {
      final data = await _client
          .from('cash_receipts')
          .select('id')
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();
      int maxId = 0;
      if (data != null && data['id'] != null) {
        maxId = data['id'] as int;
      }
      return (maxId + 1).toString();
    } catch (e) {
      return '1';
    }
  }

  void regenerateNumber() async {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      final num = await _generateReceiptNumber();
      emit(currentState.copyWith(receiptNumber: num));
    }
  }

  void setMode(CashReceiptMode m) {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      clearCustomer();
      clearSupplier();
      clearAccount();
      amountCtrl.clear();
      notesCtrl.clear();
      emit(currentState.copyWith(mode: m));
    }
  }

  Future<void> pickDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(transactionDate: picked));
    }
  }

  Future<void> searchCustomers(String q) async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return;

    if (q.trim().isEmpty) {
      emit(currentState.copyWith(customerResults: []));
      return;
    }

    emit(currentState.copyWith(isLoadingCustomers: true));
    try {
      final results = await _customerDao.search(q.trim(), limit: 20);
      emit(currentState.copyWith(
        customerResults: results,
        isLoadingCustomers: false,
      ));
    } catch (e) {
      emit(currentState.copyWith(isLoadingCustomers: false));
    }
  }

  void selectCustomer(CustomerModel c) {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      customerCtrl.text = c.name;
      emit(currentState.copyWith(
        selectedCustomer: c,
        customerResults: [],
      ));
    }
  }

  void clearCustomer() {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      customerCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedCustomer: true,
        customerResults: [],
      ));
    }
  }

  Future<void> searchSuppliers(String q) async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return;

    if (q.trim().isEmpty) {
      emit(currentState.copyWith(supplierResults: []));
      return;
    }

    emit(currentState.copyWith(isLoadingSuppliers: true));
    try {
      final results = await _supplierDao.search(q.trim(), limit: 20);
      emit(currentState.copyWith(
        supplierResults: results,
        isLoadingSuppliers: false,
      ));
    } catch (e) {
      emit(currentState.copyWith(isLoadingSuppliers: false));
    }
  }

  Future<void> selectSupplier(SupplierModel s) async {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      supplierCtrl.text = s.name;
      emit(currentState.copyWith(
        selectedSupplier: s,
        supplierResults: [],
      ));

      if (s.id != null) {
        try {
          final liveBalances = await _supplierDao.getSupplierBalancesByCurrency(s.id!);
          if (liveBalances.isNotEmpty && state is CashReceiptLoaded) {
            final latestState = state as CashReceiptLoaded;
            if (latestState.selectedSupplier?.id == s.id) {
              final updated = s.copyWith(currentBalancesByCurrency: liveBalances);
              emit(latestState.copyWith(selectedSupplier: updated));
            }
          }
        } catch (_) {}
      }
    }
  }

  void clearSupplier() {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      supplierCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedSupplier: true,
        supplierResults: [],
      ));
    }
  }

  Future<void> searchAccounts(String q) async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return;

    emit(currentState.copyWith(isLoadingAccounts: true));
    try {
      if (q.trim().isEmpty) {
        final results = await _accountDao.getAll();
        emit(currentState.copyWith(
          accountResults: results,
          isLoadingAccounts: false,
        ));
        return;
      }
      final results = await _accountDao.search(q.trim());
      emit(currentState.copyWith(
        accountResults: results,
        isLoadingAccounts: false,
      ));
    } catch (e) {
      emit(currentState.copyWith(isLoadingAccounts: false));
    }
  }

  void selectAccount(AccountModel a) {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      accountCtrl.text = '${a.displayName} (${a.code})';
      emit(currentState.copyWith(
        selectedAccount: a,
        accountResults: [],
      ));
    }
  }

  void clearAccount() {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      accountCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedAccount: true,
        accountResults: [],
      ));
    }
  }

  Future<void> loadReceipts() async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return;

    try {
      var query = _client
          .from('cash_receipts')
          .select('''
            *,
            customers(name, code),
            suppliers(name, code)
          ''');

      if (currentState.historySearchQuery.isNotEmpty) {
        final q = currentState.historySearchQuery;
        query = query.or('customers.name.ilike.%$q%,customers.code.ilike.%$q%,suppliers.name.ilike.%$q%,suppliers.code.ilike.%$q%');
      }

      if (currentState.historyFromDate != null) {
        query = query.gte('receipt_date', AppUtils.formatDateForDb(currentState.historyFromDate!));
      }
      if (currentState.historyToDate != null) {
        query = query.lte('receipt_date', AppUtils.formatDateForDb(currentState.historyToDate!));
      }

      final rows = await query.order('id', ascending: false).limit(100);
      final receipts = (rows as List).map((r) {
        final customer = AppUtils.asMap(r.remove('customers'));
        final supplier = AppUtils.asMap(r.remove('suppliers'));
        r.remove('accounts');
        return Map<String, dynamic>.from({
          ...r,
          'customer_name': customer?['name'],
          'customer_code': customer?['code'],
          'supplier_name': supplier?['name'],
          'supplier_code': supplier?['code'],
        });
      }).toList();
      emit(currentState.copyWith(receipts: receipts));
    } catch (e) {
      debugPrint('CashReceiptCubit.loadReceipts error: $e');
      emit(currentState.copyWith(receipts: []));
    }
  }

  void setHistorySearch(String query) {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      emit(currentState.copyWith(historySearchQuery: query));
      loadReceipts();
    }
  }

  Future<void> pickHistoryFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.historyFromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(historyFromDate: picked));
      loadReceipts();
    }
  }

  Future<void> pickHistoryToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.historyToDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(historyToDate: picked));
      loadReceipts();
    }
  }

  void clearHistoryFilters() {
    final currentState = state;
    if (currentState is CashReceiptLoaded) {
      emit(currentState.copyWith(
        historySearchQuery: '',
        clearHistoryFromDate: true,
        clearHistoryToDate: true,
      ));
      loadReceipts();
    }
  }

  Future<bool> save() async {
    final currentState = state;
    if (currentState is! CashReceiptLoaded) return false;

    final amountText = amountCtrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      return false;
    }

    if (currentState.mode == CashReceiptMode.customer &&
        currentState.selectedCustomer == null) {
      return false;
    }

    if (currentState.mode == CashReceiptMode.supplier &&
        currentState.selectedSupplier == null) {
      return false;
    }

    if (currentState.selectedAccount == null) {
      return false;
    }

    emit(currentState.copyWith(isSaving: true));
    try {
      final dateStr =
          AppUtils.formatDateForDb(currentState.transactionDate);
      final desc = notesCtrl.text.trim().isEmpty
          ? (currentState.mode == CashReceiptMode.customer
              ? 'استلام نقدي من العميل ${currentState.selectedCustomer!.name}'
              : currentState.mode == CashReceiptMode.supplier
                  ? 'استلام نقدي من المورد ${currentState.selectedSupplier!.name}'
                  : 'إيداع نقدي - ${currentState.selectedAccount!.name}')
          : notesCtrl.text.trim();

      final prevCashBalance = await _cashboxDao.getCurrentBalance();
      final newCashBalance = prevCashBalance + amount;

      // 1. Insert into cashbox (money IN)
      await _client.from('cashbox').insert({
        'transaction_date': dateStr,
        'type': 'debit',
        'amount': amount,
        'balance_after': newCashBalance,
        'description': desc,
        'related_transaction_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Dispatch the Business Event to the Enterprise Posting Engine
      await _client.rpc('rpc_build_cash_receipt_journal', params: {
        'payload': {
          'date': dateStr,
          'amount': amount,
          'mode': currentState.mode.name,
          'customer_id': currentState.mode == CashReceiptMode.customer
              ? currentState.selectedCustomer!.id
              : null,
          'supplier_id': currentState.mode == CashReceiptMode.supplier
              ? currentState.selectedSupplier!.id
              : null,
          'description': currentState.mode == CashReceiptMode.other
              ? '${currentState.selectedAccount?.name ?? 'إيراد'} - $desc'
              : desc,
          'idempotency_key': 'cash_rec_${currentState.receiptNumber}',
        }
      });

      // 4. Insert into cash_receipts log
      await _client.from('cash_receipts').insert({
        'receipt_number': currentState.receiptNumber,
        'receipt_date': dateStr,
        'mode': currentState.mode == CashReceiptMode.customer
            ? 'customer'
            : 'other',
        'customer_id': currentState.mode == CashReceiptMode.customer
            ? currentState.selectedCustomer!.id
            : null,
        'account_id': currentState.selectedAccount!.id,
        'amount': amount,
        'description': desc,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Reset form
      clearCustomer();
      clearSupplier();
      clearAccount();
      amountCtrl.clear();
      notesCtrl.clear();
      final newReceiptNumber = await _generateReceiptNumber();
      emit(currentState.copyWith(
        isSaving: false,
        receiptNumber: newReceiptNumber,
        transactionDate: DateTime.now(),
        clearSelectedCustomer: true,
        clearSelectedSupplier: true,
        clearSelectedAccount: true,
      ));
      await loadReceipts();

      // Notify other cubits
      DataChangeEventBus.instance.notifyCustomersChanged();
      DataChangeEventBus.instance.notifyAccountsChanged();

      return true;
    } catch (e) {
      final updatedState = state;
      if (updatedState is CashReceiptLoaded) {
        emit(updatedState.copyWith(isSaving: false));
      }
      return false;
    } finally {
      final updatedState = state;
      if (updatedState is CashReceiptLoaded) {
        emit(updatedState.copyWith(isSaving: false));
      }
    }
  }

  @override
  void onChange(Change<CashReceiptState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    amountCtrl.dispose();
    notesCtrl.dispose();
    customerCtrl.dispose();
    supplierCtrl.dispose();
    accountCtrl.dispose();
    return super.close();
  }
}
