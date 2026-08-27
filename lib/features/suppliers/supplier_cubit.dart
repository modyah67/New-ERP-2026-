import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../core/data_change_event_bus.dart';
import 'supplier_state.dart';

class SupplierCubit extends Cubit<SupplierState> {
  final SupplierDao _dao = SupplierDao();

  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';

  SupplierFormState _formState = const SupplierFormState();
  SupplierFormState get formState => _formState;

  // ── Controllers ──
  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final initialBalanceController = TextEditingController();
  String? _selectedCurrency;
  String? get selectedCurrency => _selectedCurrency;
  set selectedCurrency(String? v) { _selectedCurrency = v; }
  
  String _initialBalanceDirection = 'CREDIT';
  String get initialBalanceDirection => _initialBalanceDirection;
  set initialBalanceDirection(String v) {
    _initialBalanceDirection = v;
  }

  // ── Focus nodes ──
  final nameFocus = FocusNode();
  final phoneFocus = FocusNode();
  final addressFocus = FocusNode();
  final initialBalanceFocus = FocusNode();

  late final StreamSubscription<void> _suppliersSub;
  Timer? _debounce;

  SupplierCubit() : super(const SupplierInitial()) {
    _suppliersSub =
        DataChangeEventBus.instance.suppliersStream.listen((_) => loadAll(reset: true));
  }

  Future<void> init() async {
    await loadAll(reset: true);
  }

  // ── Form: Prepare ADD ──

  Future<void> prepareAddForm() async {
    _formState = const SupplierFormState(isEditing: false);
    _clearForm();
    _selectedCurrency = null;
    _initialBalanceDirection = 'CREDIT';
    await _generateCode();
  }

  // ── Form: Prepare EDIT ──

  Future<void> prepareEditForm(SupplierModel supplier) async {
    _formState = SupplierFormState(
      isEditing: true,
      editingSupplier: supplier,
    );
    codeController.text = supplier.supplierCode;
    nameController.text = supplier.name;
    phoneController.text = supplier.phone;
    addressController.text = supplier.address;
    initialBalanceController.text = supplier.initialBalance.toString();
    _initialBalanceDirection = supplier.initialBalanceDirection;
    _selectedCurrency = supplier.currency;
  }

  Future<void> _generateCode() async {
    try {
      final code = await _dao.generateNextCode();
      codeController.text = code.replaceAll('SUPP-', '');
    } catch (e) {
      debugPrint('SupplierCubit._generateCode error: $e');
      codeController.text = '0001';
    }
  }

  // ── Load data ──

  Future<void> loadAll({bool reset = false}) async {
    //debugPrint("loadAll called");
    //debugPrint(StackTrace.current.toString());
    if (isClosed) return;
    if (reset) {
      _offset = 0;
      _currentQuery = '';
      emit(const SupplierLoading());
    }

    final currentState = state;
    if (currentState is SupplierLoaded && !currentState.hasMore && !reset) {
      return;
    }

    try {
      final newItems = await _dao.getAll(limit: _limit, offset: _offset);
      if (isClosed) return;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(SupplierLoaded(suppliers: newItems, hasMore: hasMore));
      } else if (currentState is SupplierLoaded) {
        emit(currentState.copyWith(
          suppliers: [...currentState.suppliers, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      if (isClosed) return;
      emit(SupplierError(message: 'حدث خطأ أثناء تحميل البيانات: $e'));
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
    if (isClosed) return;
    if (reset) _offset = 0;

    final currentState = state;
    if (currentState is SupplierLoaded && !currentState.hasMore && !reset) {
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
        emit(SupplierLoaded(
          suppliers: newItems,
          searchQuery: _currentQuery,
          hasMore: hasMore,
        ));
      } else if (currentState is SupplierLoaded) {
        emit(currentState.copyWith(
          suppliers: [...currentState.suppliers, ...newItems],
          searchQuery: _currentQuery,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      if (isClosed) return;
      emit(SupplierError(message: 'حدث خطأ أثناء البحث: $e'));
    }
  }

  // ── Infinite scroll ──

  Future<void> fetchMore() async {
    final currentState = state;
    if (currentState is! SupplierLoaded) return;
    if (currentState.isFetchingMore || !currentState.hasMore) return;

    emit(currentState.copyWith(isFetchingMore: true));

    if (_currentQuery.isEmpty) {
      await loadAll();
    } else {
      await _runSearch();
    }
  }

  // ── Save ──

  Future<bool> save() async {
    if (!formKey.currentState!.validate()) return false;
    if (_selectedCurrency == null || _selectedCurrency!.isEmpty) {
      return false;
    }

    _formState = _formState.copyWith(isSaving: true);
    emit(_formState);

    try {
      final initialBal = double.tryParse(initialBalanceController.text.trim()) ?? 0.0;

      final supplierData = SupplierModel(
        id: _formState.editingSupplier?.id,
        supplierCode: codeController.text.trim(),
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
        address: addressController.text.trim(),
        initialBalance: initialBal,
        initialBalanceDirection: _initialBalanceDirection,
        currency: _selectedCurrency!,
        outstandingBalance: _formState.editingSupplier == null
            ? 0.0
            : (_formState.editingSupplier!.outstandingBalance + (initialBal - _formState.editingSupplier!.initialBalance)),
      );

      debugPrint('SupplierCubit: supplierData = ${supplierData.toInsertMap()}');

      if (_formState.editingSupplier == null) {
        await _dao.insert(supplierData);
        debugPrint('SupplierCubit: inserted supplier code=${supplierData.supplierCode}');
      } else {
        await _dao.update(supplierData);
        debugPrint('SupplierCubit: updated supplier code=${supplierData.supplierCode}');
      }

      await loadAll(reset: true);
      if (isClosed) return true;
      DataChangeEventBus.instance.notifySuppliersChanged();
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return true;
    } catch (e) {
      debugPrint('SupplierCubit.save error: $e');
      if (isClosed) return false;
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return false;
    }
  }

  // ── Delete ──

  /// Returns null on success, or the PostgREST error code on failure.
  Future<String?> deleteSupplier(String supplierCode) async {
    try {
      await _dao.delete(supplierCode);
      await loadAll(reset: true);
      if (isClosed) return null;
      DataChangeEventBus.instance.notifySuppliersChanged();
      return null;
    } on PostgrestException catch (e) {
      debugPrint('SupplierCubit.delete error: $e');
      return e.code;
    } catch (e) {
      debugPrint('SupplierCubit.delete error: $e');
      return 'unknown';
    }
  }

  // ── Helpers ──

  void _clearForm() {
    codeController.clear();
    nameController.clear();
    phoneController.clear();
    addressController.clear();
    initialBalanceController.clear();
    _selectedCurrency = null;
    _formState = _formState.copyWith(clearEditingSupplier: true);
  }

  @override
  Future<void> close() {
    _suppliersSub.cancel();
    _debounce?.cancel();
    codeController.dispose();
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    initialBalanceController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    addressFocus.dispose();
    initialBalanceFocus.dispose();
    return super.close();
  }
}