import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/models/customer_model.dart';
import '../../core/data_change_event_bus.dart';
import 'customer_state.dart';

class CustomerCubit extends Cubit<CustomerState> {
  final CustomerDao _dao = CustomerDao();

  // ── Pagination ──
  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';

  // ── Form state ──
  CustomerFormState _formState = const CustomerFormState();
  CustomerFormState get formState => _formState;

  // ── Core fields ──
  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final cityController = TextEditingController();
  final countryController = TextEditingController();
  final gmailController = TextEditingController();
  final vatController = TextEditingController();
  final eoriController = TextEditingController();

  // ── Contact person fields ──
  final contactNameController = TextEditingController();
  final contactPhoneController = TextEditingController();
  final contactEmailController = TextEditingController();

  // ── Initial balance ──
  final initialBalanceController = TextEditingController();

  // ── Currency ──
  String? selectedCurrency;

  // ── Initial Balance Direction ──
  String initialBalanceDirection = 'DEBIT';

  // ── Focus nodes ──
  final nameFocus = FocusNode();
  final phoneFocus = FocusNode();
  final cityFocus = FocusNode();
  final countryFocus = FocusNode();
  final gmailFocus = FocusNode();
  final vatFocus = FocusNode();
  final eoriFocus = FocusNode();
  final contactNameFocus = FocusNode();
  final contactPhoneFocus = FocusNode();
  final contactEmailFocus = FocusNode();

  // ── Addresses (raw maps) ──
  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> get addresses => List.unmodifiable(_addresses);

  // ── Stream ──
  late final StreamSubscription<void> _customersSub;
  Timer? _debounce;

  CustomerCubit() : super(const CustomerInitial()) {
    _customersSub =
        DataChangeEventBus.instance.customersStream.listen((_) => loadAll(reset: true));
  }

  // ── Initialization ──

  Future<void> init() async {
    await loadAll(reset: true);
  }

  Future<void> prepareAddForm() async {
    _formState = const CustomerFormState(isEditing: false);
    _clearForm();
    initialBalanceDirection = 'DEBIT';
    await _generateCode();
  }

  Future<void> prepareEditForm(CustomerModel customer) async {
    _formState = CustomerFormState(
      isEditing: true,
      editingCustomer: customer,
    );
    codeController.text = customer.code;
    nameController.text = customer.name;
    phoneController.text = customer.phone;
    cityController.text = customer.city;
    countryController.text = customer.country;
    gmailController.text = customer.gmail;
    vatController.text = customer.vatNumber;
    eoriController.text = customer.eoriNo;
    contactNameController.text = customer.contactPersonName;
    contactPhoneController.text = customer.contactPersonPhone;
    contactEmailController.text = customer.contactPersonEmail;
    initialBalanceController.text = customer.initialBalance == 0.0 ? '' : customer.initialBalance.toString();
    initialBalanceDirection = customer.initialBalanceDirection;
    selectedCurrency = customer.currency;
    _addresses = customer.addresses.map((a) => Map<String, dynamic>.from(a)).toList();
  }

  Future<void> _generateCode() async {
    try {
      final code = await _dao.generateNextCode();
      if (isClosed) return;
      codeController.text = code.replaceAll(RegExp(r'^[A-Z]+-'), '');
    } catch (e) {
      debugPrint('CustomerCubit._generateCode error: $e');
      if (!isClosed) codeController.text = '0001';
    }
  }

  // ── Load data ──

  Future<void> loadAll({bool reset = false}) async {
    if (isClosed) return;
    if (reset) {
      _offset = 0;
      _currentQuery = '';
      emit(const CustomerLoading());
    }

    final currentState = state;
    if (currentState is CustomerLoaded && !currentState.hasMore && !reset) {
      return;
    }

    try {
      final newItems = await _dao.getAll(limit: _limit, offset: _offset);
      if (isClosed) return;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(CustomerLoaded(customers: newItems, hasMore: hasMore));
      } else if (currentState is CustomerLoaded) {
        emit(currentState.copyWith(
          customers: [...currentState.customers, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(CustomerError(message: 'حدث خطأ أثناء تحميل البيانات: $e'));
    }
  }

  // ── Search ──

  void onSearchChanged(String query) {
    _currentQuery = query.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(reset: true);
    });
  }

  Future<void> _runSearch({bool reset = false}) async {
    if (reset) _offset = 0;

    final currentState = state;
    if (currentState is CustomerLoaded && !currentState.hasMore && !reset) {
      return;
    }

    try {
      if (_currentQuery.isEmpty) {
        await loadAll(reset: reset);
        return;
      }

      final newItems = await _dao.search(_currentQuery, limit: _limit, offset: _offset);
      if (isClosed) return;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(CustomerLoaded(
          customers: newItems,
          searchQuery: _currentQuery,
          hasMore: hasMore,
        ));
      } else if (currentState is CustomerLoaded) {
        emit(currentState.copyWith(
          customers: [...currentState.customers, ...newItems],
          searchQuery: _currentQuery,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(CustomerError(message: 'حدث خطأ أثناء البحث: $e'));
    }
  }

  // ── Infinite scroll ──

  Future<void> fetchMore() async {
    final currentState = state;
    if (currentState is! CustomerLoaded) return;
    if (currentState.isFetchingMore || !currentState.hasMore) return;

    emit(currentState.copyWith(isFetchingMore: true));

    if (_currentQuery.isEmpty) {
      await loadAll();
    } else {
      await _runSearch();
    }
  }

  // ── Address management ──

  void setAddresses(List<Map<String, dynamic>> addresses) {
    _addresses = List.from(addresses);
  }

  void setSingleAddress(String text) {
    if (text.isEmpty) {
      _addresses = [];
    } else {
      _addresses = [
        {
          'address_line_1': text,
          'city': '',
          'country': '',
          'type': 'quick',
        }
      ];
    }
    emit(_formState.copyWith(addressesVersion: DateTime.now().millisecondsSinceEpoch));
  }

  void addQuickAddress(String text) {
    _addresses.add({
      'address_line_1': text,
      'city': '',
      'country': '',
      'type': 'quick',
    });
    emit(_formState.copyWith(addressesVersion: DateTime.now().millisecondsSinceEpoch));
  }

  void addFullAddress({required String city, required String country, required String address}) {
    _addresses.add({
      'address_line_1': address,
      'city': city,
      'country': country,
      'type': 'full',
    });
    emit(_formState.copyWith(addressesVersion: DateTime.now().millisecondsSinceEpoch));
  }

  void removeAddress(int index) {
    if (index >= 0 && index < _addresses.length) {
      _addresses.removeAt(index);
      emit(_formState.copyWith(addressesVersion: DateTime.now().millisecondsSinceEpoch));
    }
  }

  void updateAddressField(int index, String field, String value) {
    if (index >= 0 && index < _addresses.length) {
      _addresses[index][field] = value;
    }
  }

  // ── Save ──

  Future<bool> save() async {
    if (!formKey.currentState!.validate()) return false;
    if (selectedCurrency == null || selectedCurrency!.isEmpty) {
      return false;
    }

    _formState = _formState.copyWith(isSaving: true);
    emit(_formState);

    final now = DateTime.now().toIso8601String();

    try {
      if (_formState.editingCustomer == null) {
        final newCustomer = CustomerModel(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          city: cityController.text.trim(),
          country: countryController.text.trim(),
          gmail: gmailController.text.trim(),
          vatNumber: vatController.text.trim(),
          eoriNo: eoriController.text.trim(),
          contactPersonName: contactNameController.text.trim(),
          contactPersonPhone: contactPhoneController.text.trim(),
          contactPersonEmail: contactEmailController.text.trim(),
          addresses: List.from(_addresses),
          balance: 0.0,
          initialBalance: double.tryParse(initialBalanceController.text.trim()) ?? 0.0,
          initialBalanceDirection: initialBalanceDirection,
          currency: selectedCurrency!,
          createdAt: now,
        );

        final newId = await _dao.insert(newCustomer);
      } else {
        final oldInitial = _formState.editingCustomer!.initialBalance;
        final newInitial = double.tryParse(initialBalanceController.text.trim()) ?? 0.0;
        final delta = newInitial - oldInitial;
        final oldBalance = _formState.editingCustomer!.balance;
        final newBalance = oldBalance + delta;

        final updated = _formState.editingCustomer!.copyWith(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          city: cityController.text.trim(),
          country: countryController.text.trim(),
          gmail: gmailController.text.trim(),
          vatNumber: vatController.text.trim(),
          eoriNo: eoriController.text.trim(),
          contactPersonName: contactNameController.text.trim(),
          contactPersonPhone: contactPhoneController.text.trim(),
          contactPersonEmail: contactEmailController.text.trim(),
          addresses: List.from(_addresses),
          balance: newBalance,
          initialBalance: newInitial,
          initialBalanceDirection: initialBalanceDirection,
          currency: selectedCurrency!,
        );

        await _dao.updateCustomer(updated);
        debugPrint('CustomerCubit: updated customer id=${updated.id}');
      }

      if (isClosed) return false;
      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyCustomersChanged();
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return true;
    } catch (e) {
      debugPrint('CustomerCubit.save error: $e');
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return false;
    }
  }

  // ── Delete ──

  /// Deletes a customer with admin password verification + server-side checks.
  /// Returns null on success, or an error code string on failure.
  /// Error codes: 'wrong_password', 'has_dependencies', 'not_admin', 'unknown'
  Future<String?> deleteCustomer(CustomerModel customer, String adminPassword) async {
    try {
      // 1. Re-authenticate admin password via Supabase Auth
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null || email.isEmpty) {
        debugPrint('CustomerCubit.delete: no current user email');
        return 'unknown';
      }
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: adminPassword,
        );
      } on AuthException {
        return 'wrong_password';
      }

      // 2. Call RPC which checks admin + dependencies + deletes
      final result = await _dao.deleteSafe(customer.id!);
      final error = result['error'] as String?;
      if (error == 'NOT_ADMIN') {
        return 'not_admin';
      }
      if (error == 'HAS_DEPENDENCIES') {
        return 'has_dependencies';
      }

      // 3. Success
      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyCustomersChanged();
      return null;
    } catch (e) {
      debugPrint('CustomerCubit.delete error: $e');
      return 'unknown';
    }
  }

  // ── Helpers ──

  void _clearForm() {
    codeController.clear();
    nameController.clear();
    phoneController.clear();
    cityController.clear();
    countryController.clear();
    gmailController.clear();
    vatController.clear();
    eoriController.clear();
    contactNameController.clear();
    contactPhoneController.clear();
    contactEmailController.clear();
    initialBalanceController.clear();
    selectedCurrency = null;
    _addresses = [];
    _formState = _formState.copyWith(clearEditingCustomer: true);
  }

  @override
  Future<void> close() {
    _customersSub.cancel();
    _debounce?.cancel();
    codeController.dispose();
    nameController.dispose();
    phoneController.dispose();
    cityController.dispose();
    countryController.dispose();
    gmailController.dispose();
    vatController.dispose();
    eoriController.dispose();
    contactNameController.dispose();
    contactPhoneController.dispose();
    contactEmailController.dispose();
    initialBalanceController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    cityFocus.dispose();
    countryFocus.dispose();
    gmailFocus.dispose();
    vatFocus.dispose();
    eoriFocus.dispose();
    contactNameFocus.dispose();
    contactPhoneFocus.dispose();
    contactEmailFocus.dispose();
    return super.close();
  }
}
