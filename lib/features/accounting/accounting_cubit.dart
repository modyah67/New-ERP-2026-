import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../../data/dao/account_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/models/account_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../core/data_change_event_bus.dart';
import 'accounting_state.dart';

class AccountingCubit extends Cubit<AccountingState> {
  final _client = Supabase.instance.client;
  final CustomerDao _customerDao = CustomerDao();
  final SupplierDao _supplierDao = SupplierDao();
  final AccountDao _accountDao = AccountDao();
  final TransactionDao _transactionDao = TransactionDao();

  var formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final notesController = TextEditingController();

  // ── Selection state (mutable, outside of Equatable state) ──
  String customerSearchText = '';
  String supplierSearchText = '';
  CustomerModel? selectedCustomer;
  SupplierModel? selectedSupplier;
  AccountModel? selectedAccount;
  bool accountValidated = false;

  AccountingCubit() : super(const AccountingInitial()) {
    _loadFormData();
  }

  @override
  void onChange(Change<AccountingState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    amountController.dispose();
    notesController.dispose();
    return super.close();
  }

  Future<void> _loadFormData() async {
    emit(const AccountingLoading());
    try {
      final customers = await _customerDao.getAll(limit: 2000, offset: 0);
      final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
      final accounts = await _accountDao.getAll();
      emit(AccountingLoaded(
        customers: customers,
        suppliers: suppliers,
        accounts: accounts,
        entryDate: DateTime.now(),
      ));
    } catch (e) {
      emit(AccountingError(message: 'حدث خطأ: $e'));
    }
  }

  void prepareForm() {
    amountController.clear();
    notesController.clear();
    selectedCustomer = null;
    selectedSupplier = null;
    selectedAccount = null;
    accountValidated = false;
    formKey.currentState?.reset();
    _loadFormData();
  }

  Future<void> pickDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! AccountingLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.entryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(entryDate: picked));
    }
  }

  List<CustomerModel> filterCustomersByQuery(String query) {
    final currentState = state;
    if (currentState is! AccountingLoaded) return [];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return currentState.customers;
    return currentState.customers.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.id.toString().toLowerCase().contains(q);
    }).toList();
  }

  List<SupplierModel> filterSuppliersByQuery(String query) {
    final currentState = state;
    if (currentState is! AccountingLoaded) return [];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return currentState.suppliers;
    return currentState.suppliers.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.supplierCode.toLowerCase().contains(q);
    }).toList();
  }

  List<AccountModel> filterAccountsByQuery(String query) {
    final currentState = state;
    if (currentState is! AccountingLoaded) return [];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return currentState.accounts;
    return currentState.accounts.where((a) {
      return a.name.toLowerCase().contains(q) ||
          a.code.toLowerCase().contains(q);
    }).toList();
  }

  Future<bool> saveEntry(String entryType) async {
    final currentState = state;
    if (currentState is! AccountingLoaded) return false;
    if (currentState.isSaving) return false;

    if (selectedAccount == null) {
      accountValidated = true;
      return false;
    }
    if (formKey.currentState == null || !formKey.currentState!.validate()) {
      return false;
    }
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0) return false;

    final isCustomer = entryType.contains('customer');
    final isDebit = entryType.startsWith('debit_');
    final selectedParty =
        isCustomer ? selectedCustomer?.id : selectedSupplier?.supplierCode;
    if (selectedParty == null) return false;

    emit(currentState.copyWith(isSaving: true));
    try {
      final txDate = AppUtils.formatDateForDb(currentState.entryDate);
      final description = notesController.text.trim().isEmpty
          ? 'قيد محاسبي'
          : notesController.text.trim();

      // 2. Dispatch the Business Event to the Enterprise Posting Engine
      await _client.rpc('rpc_build_party_adjustment_journal', params: {
        'payload': {
          'date': txDate,
          'amount': amount,
          'party_type': isCustomer ? 'customer' : 'supplier',
          'party_id': isCustomer ? selectedCustomer!.id : selectedSupplier!.id,
          'is_debit': isDebit,
          'description': '${selectedAccount?.name ?? 'تسوية'} - $description',
        }
      });

      return true;
    } catch (e) {
      emit(AccountingError(message: 'حدث خطأ أثناء الحفظ: $e'));
      return false;
    } finally {
      final updatedState = state;
      if (updatedState is AccountingLoaded) {
        emit(updatedState.copyWith(isSaving: false));
      }
    }
  }

  Future<void> postSaveRefresh(bool isCustomer) async {
    DataChangeEventBus.instance.notifyAccountsChanged();
    if (isCustomer) {
      DataChangeEventBus.instance.notifyCustomersChanged();
    } else {
      DataChangeEventBus.instance.notifySuppliersChanged();
    }
    await _loadFormData();
  }
}
