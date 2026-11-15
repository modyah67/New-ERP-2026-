import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/models/transport_supplier_model.dart';
import '../../core/data_change_event_bus.dart';
import 'transport_supplier_state.dart';

class TransportSupplierCubit extends Cubit<TransportSupplierState> {
  final TransportSupplierDao _dao = TransportSupplierDao();

  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';

  TransportSupplierFormState _formState = const TransportSupplierFormState();
  TransportSupplierFormState get formState => _formState;

  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final initialBalanceController = TextEditingController(text: '0.00');
  final initialTruckBalanceController = TextEditingController();
  final notesController = TextEditingController();

  String initialBalanceDirection = 'CREDIT';

  late final StreamSubscription<void> _sub;
  Timer? _debounce;

  TransportSupplierCubit() : super(const TransportSupplierInitial()) {
    _sub = DataChangeEventBus.instance.transportSuppliersStream
        .listen((_) => loadAll(reset: true));
  }

  Future<void> init() async => await loadAll(reset: true);

  Future<void> prepareAddForm() async {
    _formState = const TransportSupplierFormState(isEditing: false);
    _clearForm();
    initialBalanceController.text = '0.00';
    initialBalanceDirection = 'CREDIT';
    codeController.text = await _dao.generateNextCode();
  }

  Future<void> prepareEditForm(TransportSupplierModel supplier) async {
    _formState = TransportSupplierFormState(
        isEditing: true, editingSupplier: supplier);
    codeController.text = supplier.code;
    nameController.text = supplier.name;
    phoneController.text = supplier.phone;
    emailController.text = supplier.email;
    initialBalanceDirection = supplier.initialBalanceDirection;
    initialBalanceController.text = supplier.initialBalance == 0.0
        ? '0.00'
        : supplier.initialBalance.toString();
    initialTruckBalanceController.text = supplier.initialTruckBalance > 0
        ? (supplier.initialTruckBalance % 1 == 0
            ? supplier.initialTruckBalance.toInt().toString()
            : supplier.initialTruckBalance.toString())
        : '';
    notesController.text = supplier.notes ?? '';
  }

  Future<void> loadAll({bool reset = false}) async {
    if (isClosed) return;
    if (reset) {
      _offset = 0;
      _currentQuery = '';
      emit(const TransportSupplierLoading());
    }

    final currentState = state;
    if (currentState is TransportSupplierLoaded &&
        !currentState.hasMore &&
        !reset) {
      return;
    }

    try {
      final newItems = await _dao.getAll(limit: _limit, offset: _offset);
      if (isClosed) return;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(TransportSupplierLoaded(suppliers: newItems, hasMore: hasMore));
      } else if (currentState is TransportSupplierLoaded) {
        emit(currentState.copyWith(
          suppliers: [...currentState.suppliers, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(TransportSupplierError(
          message: 'حدث خطأ أثناء تحميل البيانات: $e'));
    }
  }

  void onSearchChanged(String query) {
    _currentQuery = query.trim();
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 300), () => _runSearch(reset: true));
  }

  Future<void> _runSearch({bool reset = false}) async {
    if (_currentQuery.isEmpty) {
      await loadAll(reset: true);
      return;
    }

    if (reset) {
      _offset = 0;
      emit(const TransportSupplierLoading());
    }

    try {
      final results = await _dao.search(_currentQuery,
          limit: _limit, offset: _offset);
      if (isClosed) return;
      final hasMore = results.length >= _limit;
      _offset += _limit;

      final currentState = state;
      if (reset || currentState is! TransportSupplierLoaded) {
        emit(TransportSupplierLoaded(suppliers: results, hasMore: hasMore));
      } else {
        emit(currentState.copyWith(
          suppliers: [...currentState.suppliers, ...results],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(TransportSupplierError(message: 'فشل البحث: $e'));
    }
  }

  Future<bool> saveSupplier() async {
    if (!formKey.currentState!.validate()) return false;

    try {
      final initialBal =
          double.tryParse(initialBalanceController.text.trim()) ?? 0.0;
      final initialTruckBal =
          double.tryParse(initialTruckBalanceController.text.trim()) ?? 0.0;

      if (_formState.isEditing && _formState.editingSupplier != null) {
        final updated = _formState.editingSupplier!.copyWith(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          email: emailController.text.trim(),
          initialBalance: initialBal,
          initialTruckBalance: initialTruckBal,
          initialBalanceDirection: initialBalanceDirection,
          notes: notesController.text.trim(),
        );
        await _dao.update(updated);
      } else {
        final newSupplier = TransportSupplierModel(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          email: emailController.text.trim(),
          initialBalance: initialBal,
          initialTruckBalance: initialTruckBal,
          initialBalanceDirection: initialBalanceDirection,
          notes: notesController.text.trim(),
          createdAt: DateTime.now().toIso8601String(),
        );
        await _dao.create(newSupplier);
      }

      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      DataChangeEventBus.instance.notifyAccountsChanged();
      return true;
    } catch (e) {
      emit(TransportSupplierError(message: 'فشل حفظ مورد النقل: $e'));
      return false;
    }
  }

  Future<bool> deleteSupplier(int id) async {
    try {
      await _dao.delete(id);
      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      DataChangeEventBus.instance.notifyAccountsChanged();
      return true;
    } catch (e) {
      emit(TransportSupplierError(message: 'فشل حذف مورد النقل: $e'));
      return false;
    }
  }

  Future<bool> recordInvoice({
    required int supplierId,
    required double amount,
    num numberOfTrucks = 1,
    String? routeFrom,
    String? routeTo,
    DateTime? date,
    String? description,
    int? expenseAccountId,
    String? referenceNumber,
    String? notes,
  }) async {
    try {
      final res = await _dao.recordInvoice(
        supplierId: supplierId,
        amount: amount,
        numberOfTrucks: numberOfTrucks,
        routeFrom: routeFrom,
        routeTo: routeTo,
        date: date,
        description: description,
        expenseAccountId: expenseAccountId,
        referenceNumber: referenceNumber,
        notes: notes,
      );

      if (res['success'] == true) {
        DataChangeEventBus.instance.notifyTransportSuppliersChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();
        return true;
      }
      return false;
    } catch (e) {
      emit(TransportSupplierError(message: 'فشل تسجيل استحقاق النقل: $e'));
      return false;
    }
  }

  void _clearForm() {
    codeController.clear();
    nameController.clear();
    phoneController.clear();
    emailController.clear();
    initialBalanceController.text = '0.00';
    initialTruckBalanceController.clear();
    notesController.clear();
    initialBalanceDirection = 'CREDIT';
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
    initialTruckBalanceController.dispose();
    notesController.dispose();
    return super.close();
  }
}
