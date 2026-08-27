import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/dao/shipment_cost_item_dao.dart';
import '../../data/models/shipping_company_model.dart';
import '../../core/data_change_event_bus.dart';
import 'shipping_company_state.dart';

class ShippingCompanyCubit extends Cubit<ShippingCompanyState> {
  final ShippingCompanyDao _dao = ShippingCompanyDao();

  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';

  ShippingCompanyFormState _formState = const ShippingCompanyFormState();
  ShippingCompanyFormState get formState => _formState;

  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final initialBalanceController = TextEditingController();

  String? selectedCurrency;
  String initialBalanceDirection = 'CREDIT';

  late final StreamSubscription<void> _sub;
  Timer? _debounce;

  ShippingCompanyCubit() : super(const ShippingCompanyInitial()) {
    _sub = DataChangeEventBus.instance.shippingCompaniesStream
        .listen((_) => loadAll(reset: true));
  }

  Future<void> init() async => await loadAll(reset: true);

  Future<void> prepareAddForm() async {
    _formState = const ShippingCompanyFormState(isEditing: false);
    _clearForm();
    initialBalanceDirection = 'CREDIT';
    codeController.text = await _dao.generateNextCode();
  }

  Future<void> prepareEditForm(ShippingCompanyModel company) async {
    _formState =
        ShippingCompanyFormState(isEditing: true, editingCompany: company);
    codeController.text = company.code;
    nameController.text = company.name;
    phoneController.text = company.phone;
    emailController.text = company.email;
    selectedCurrency = company.currency;
    initialBalanceDirection = company.initialBalanceDirection;
    initialBalanceController.text = company.initialBalance == 0.0
        ? ''
        : company.initialBalance.toString();
  }

  Future<void> loadAll({bool reset = false}) async {
    if (isClosed) return;
    if (reset) {
      _offset = 0;
      _currentQuery = '';
      emit(const ShippingCompanyLoading());
    }

    final currentState = state;
    if (currentState is ShippingCompanyLoaded &&
        !currentState.hasMore &&
        !reset) return;

    try {
      final newItems = await _dao.getAll(limit: _limit, offset: _offset);
      if (isClosed) return;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(ShippingCompanyLoaded(companies: newItems, hasMore: hasMore));
      } else if (currentState is ShippingCompanyLoaded) {
        emit(currentState.copyWith(
          companies: [...currentState.companies, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(ShippingCompanyError(
          message: 'حدث خطأ أثناء تحميل البيانات: $e'));
    }
  }

  void onSearchChanged(String query) {
    _currentQuery = query.trim();
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _runSearch(reset: true));
  }

  Future<void> _runSearch({bool reset = false}) async {
    if (reset) _offset = 0;
    final currentState = state;
    if (currentState is ShippingCompanyLoaded &&
        !currentState.hasMore &&
        !reset) return;

    try {
      if (_currentQuery.isEmpty) {
        await loadAll(reset: reset);
        return;
      }

      final newItems = await _dao.search(
        _currentQuery,
        limit: _limit,
        offset: _offset,
      );
      if (isClosed) return;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(ShippingCompanyLoaded(
            companies: newItems,
            searchQuery: _currentQuery,
            hasMore: hasMore));
      } else if (currentState is ShippingCompanyLoaded) {
        emit(currentState.copyWith(
          companies: [...currentState.companies, ...newItems],
          searchQuery: _currentQuery,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(ShippingCompanyError(message: 'حدث خطأ أثناء البحث: $e'));
    }
  }

  Future<void> fetchMore() async {
    final currentState = state;
    if (currentState is! ShippingCompanyLoaded) return;
    if (currentState.isFetchingMore || !currentState.hasMore) return;
    emit(currentState.copyWith(isFetchingMore: true));
    _currentQuery.isEmpty ? await loadAll() : await _runSearch();
  }

  Future<bool> save() async {
    if (!formKey.currentState!.validate()) return false;
    if (selectedCurrency == null || selectedCurrency!.isEmpty) {
      return false;
    }

    _formState = _formState.copyWith(isSaving: true);
    emit(_formState);
    final now = DateTime.now().toIso8601String();

    try {
      if (_formState.editingCompany == null) {
        final newCompany = ShippingCompanyModel(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          email: emailController.text.trim(),
          balance: double.tryParse(initialBalanceController.text.trim()) ?? 0.0,
          initialBalance:
              double.tryParse(initialBalanceController.text.trim()) ?? 0.0,
          initialBalanceDirection: initialBalanceDirection,
          currency: selectedCurrency!,
          createdAt: now,
        );
        await _dao.insert(newCompany);
      } else {
        final updated = _formState.editingCompany!.copyWith(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          email: emailController.text.trim(),
          initialBalance:
              double.tryParse(initialBalanceController.text.trim()) ?? 0.0,
          initialBalanceDirection: initialBalanceDirection,
        );
        await _dao.update(updated);
      }

      await loadAll(reset: true);
      if (isClosed) return false;
      await ShipmentCostItemDao().updateVendorBalances();
      if (isClosed) return false;
      DataChangeEventBus.instance.notifyShippingCompaniesChanged();
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return true;
    } catch (e, st) {
      debugPrint('🔴 ShippingCompanyCubit.save FAILED');
      debugPrint('ERROR: $e');
      debugPrint('STACKTRACE: $st');

      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return false;
    }
  }

  Future<bool> deleteCompany(ShippingCompanyModel company) async {
    try {
      await _dao.delete(company.id!);
      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyShippingCompaniesChanged();
      return true;
    } catch (e) {
      return false;
    }
  }

  void _clearForm() {
    codeController.clear();
    nameController.clear();
    phoneController.clear();
    emailController.clear();
    initialBalanceController.clear();
    selectedCurrency = null;
    _formState = _formState.copyWith(clearEditingCompany: true);
  }

  @override
  Future<void> close() {
    _sub.cancel();
    _debounce?.cancel();
    codeController.dispose();
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    initialBalanceController.dispose();
    return super.close();
  }
}
