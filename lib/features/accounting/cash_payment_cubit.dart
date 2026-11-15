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
import 'cash_payment_state.dart';

class CashPaymentCubit extends Cubit<CashPaymentState> {
  final AccountDao _accountDao = AccountDao();
  final CustomerDao _customerDao = CustomerDao();
  final SupplierDao _supplierDao = SupplierDao();
  final CashboxDao _cashboxDao = CashboxDao();
  final TransactionDao _transactionDao = TransactionDao();
  final _client = Supabase.instance.client;

  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final supplierCtrl = TextEditingController();
  final customerCtrl = TextEditingController();
  final accountCtrl = TextEditingController();

  List<SupplierModel> get supplierResults {
    final s = state;
    return s is CashPaymentLoaded ? s.supplierResults : [];
  }

  List<CustomerModel> get customerResults {
    final s = state;
    return s is CashPaymentLoaded ? s.customerResults : [];
  }

  List<AccountModel> get accountResults {
    final s = state;
    return s is CashPaymentLoaded ? s.accountResults : [];
  }

  CashPaymentCubit() : super(const CashPaymentInitial()) {
    _init();
  }

  @override
  void emit(CashPaymentState state) {
    if (isClosed) return;
    super.emit(state);
  }

  Future<void> _init() async {
    final paymentNumber = await _generatePaymentNumber();
    emit(CashPaymentLoaded(
      paymentNumber: paymentNumber,
      transactionDate: DateTime.now(),
    ));
    await loadPayments();
  }

  Future<String> _generatePaymentNumber() async {
    try {
      final data = await _client
          .from('cash_payments')
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
    if (currentState is CashPaymentLoaded) {
      final num = await _generatePaymentNumber();
      emit(currentState.copyWith(paymentNumber: num));
    }
  }

  void setMode(CashPaymentMode m) {
    final currentState = state;
    if (currentState is CashPaymentLoaded) {
      clearSupplier();
      clearCustomer();
      clearAccount();
      amountCtrl.clear();
      notesCtrl.clear();
      emit(currentState.copyWith(mode: m));
    }
  }

  Future<void> pickDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return;

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

  Future<void> searchSuppliers(String q) async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return;

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

  void selectSupplier(SupplierModel s) {
    final currentState = state;
    if (currentState is CashPaymentLoaded) {
      supplierCtrl.text = s.name;
      emit(currentState.copyWith(
        selectedSupplier: s,
        supplierResults: [],
      ));
    }
  }

  void clearSupplier() {
    final currentState = state;
    if (currentState is CashPaymentLoaded) {
      supplierCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedSupplier: true,
        supplierResults: [],
      ));
    }
  }

  Future<void> searchCustomers(String q) async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return;

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
    if (currentState is CashPaymentLoaded) {
      customerCtrl.text = c.name;
      emit(currentState.copyWith(
        selectedCustomer: c,
        customerResults: [],
      ));
    }
  }

  void clearCustomer() {
    final currentState = state;
    if (currentState is CashPaymentLoaded) {
      customerCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedCustomer: true,
        customerResults: [],
      ));
    }
  }

  Future<void> searchAccounts(String q) async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return;

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
    if (currentState is CashPaymentLoaded) {
      accountCtrl.text = a.name;
      emit(currentState.copyWith(
        selectedAccount: a,
        accountResults: [],
      ));
    }
  }

  void clearAccount() {
    final currentState = state;
    if (currentState is CashPaymentLoaded) {
      accountCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedAccount: true,
        accountResults: [],
      ));
    }
  }

  Future<void> loadPayments() async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return;

    try {
      var query = _client
          .from('cash_payments')
          .select('''
            *,
            suppliers(name, code),
            customers(name, code)
          ''');

      if (currentState.historySearchQuery.isNotEmpty) {
        final q = currentState.historySearchQuery;
        query = query.or('suppliers.name.ilike.%$q%,suppliers.code.ilike.%$q%,customers.name.ilike.%$q%,customers.code.ilike.%$q%');
      }

      if (currentState.historyFromDate != null) {
        query = query.gte('payment_date', AppUtils.formatDateForDb(currentState.historyFromDate!));
      }
      if (currentState.historyToDate != null) {
        query = query.lte('payment_date', AppUtils.formatDateForDb(currentState.historyToDate!));
      }

      final rows = await query.order('id', ascending: false).limit(100);
      final payments = (rows as List).map((r) {
        final supplier = AppUtils.asMap(r.remove('suppliers'));
        final customer = AppUtils.asMap(r.remove('customers'));
        r.remove('accounts');
        return Map<String, dynamic>.from({
          ...r,
          'supplier_name': supplier?['name'],
          'supplier_code': supplier?['code'],
          'customer_name': customer?['name'],
          'customer_code': customer?['code'],
        });
      }).toList();
      emit(currentState.copyWith(payments: payments));
    } catch (e) {
      debugPrint('CashPaymentCubit.loadPayments error: $e');
      emit(currentState.copyWith(payments: []));
    }
  }

  void setHistorySearch(String query) {
    final currentState = state;
    if (currentState is CashPaymentLoaded) {
      emit(currentState.copyWith(historySearchQuery: query));
      loadPayments();
    }
  }

  Future<void> pickHistoryFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.historyFromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(historyFromDate: picked));
      loadPayments();
    }
  }

  Future<void> pickHistoryToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.historyToDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(historyToDate: picked));
      loadPayments();
    }
  }

  void clearHistoryFilters() {
    final currentState = state;
    if (currentState is CashPaymentLoaded) {
      emit(currentState.copyWith(
        historySearchQuery: '',
        clearHistoryFromDate: true,
        clearHistoryToDate: true,
      ));
      loadPayments();
    }
  }

  Future<bool> save() async {
    final currentState = state;
    if (currentState is! CashPaymentLoaded) return false;

    final amountText = amountCtrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      return false;
    }

    if (currentState.mode == CashPaymentMode.supplier &&
        currentState.selectedSupplier == null) {
      return false;
    }

    if (currentState.mode == CashPaymentMode.customer &&
        currentState.selectedCustomer == null) {
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
          ? (currentState.mode == CashPaymentMode.supplier
              ? 'صرف نقدي للمورد ${currentState.selectedSupplier!.name}'
              : currentState.mode == CashPaymentMode.customer
                  ? 'صرف نقدي للعميل ${currentState.selectedCustomer!.name}'
                  : 'صرف نقدي - ${currentState.selectedAccount!.name}')
          : notesCtrl.text.trim();

      final prevCashBalance = await _cashboxDao.getCurrentBalance();
      final newCashBalance = prevCashBalance - amount;

      // 1. Insert into cashbox (money OUT) -> type credit
      await _client.from('cashbox').insert({
        'transaction_date': dateStr,
        'type': 'credit',
        'amount': amount,
        'balance_after': newCashBalance,
        'description': desc,
        'related_transaction_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Dispatch the Business Event to the Enterprise Posting Engine
      await _client.rpc('rpc_build_cash_payment_journal', params: {
        'payload': {
          'date': dateStr,
          'amount': amount,
          'mode': currentState.mode.name,
          'supplier_id': currentState.mode == CashPaymentMode.supplier
              ? currentState.selectedSupplier!.id
              : null,
          'customer_id': currentState.mode == CashPaymentMode.customer
              ? currentState.selectedCustomer!.id
              : null,
          'description': currentState.mode == CashPaymentMode.other
              ? '${currentState.selectedAccount?.name ?? 'مصروف'} - $desc'
              : desc,
          'idempotency_key': 'cash_pay_${currentState.paymentNumber}',
        }
      });

      // 4. Insert into cash_payments log
      await _client.from('cash_payments').insert({
        'payment_number': currentState.paymentNumber,
        'payment_date': dateStr,
        'mode': currentState.mode == CashPaymentMode.supplier
            ? 'supplier'
            : currentState.mode == CashPaymentMode.customer
                ? 'customer'
                : 'other',
        'supplier_id': currentState.mode == CashPaymentMode.supplier
            ? currentState.selectedSupplier!.id
            : null,
        'customer_id': currentState.mode == CashPaymentMode.customer
            ? currentState.selectedCustomer!.id
            : null,
          'account_id': currentState.selectedAccount!.id != null
              ? int.tryParse(currentState.selectedAccount!.id!)
              : null,
        'amount': amount,
        'payment_method': 'cash',
        'description': desc,
        'created_at': DateTime.now().toIso8601String(),
      });
      clearSupplier();
      clearCustomer();
      clearAccount();
      amountCtrl.clear();
      notesCtrl.clear();
      final newPaymentNumber = await _generatePaymentNumber();
      emit(currentState.copyWith(
        isSaving: false,
        paymentNumber: newPaymentNumber,
        transactionDate: DateTime.now(),
        clearSelectedSupplier: true,
        clearSelectedCustomer: true,
        clearSelectedAccount: true,
      ));
      await loadPayments();

      // Notify other cubits
      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyCustomersChanged();
      DataChangeEventBus.instance.notifyAccountsChanged();

      return true;
    } catch (e) {
      final updatedState = state;
      if (updatedState is CashPaymentLoaded) {
        emit(updatedState.copyWith(isSaving: false));
      }
      return false;
    } finally {
      final updatedState = state;
      if (updatedState is CashPaymentLoaded) {
        emit(updatedState.copyWith(isSaving: false));
      }
    }
  }

  @override
  void onChange(Change<CashPaymentState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    amountCtrl.dispose();
    notesCtrl.dispose();
    supplierCtrl.dispose();
    customerCtrl.dispose();
    accountCtrl.dispose();
    return super.close();
  }
}
