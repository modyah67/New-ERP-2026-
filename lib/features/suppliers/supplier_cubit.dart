import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/transport_supplier_model.dart';
import '../../data/services/currency_conversion_service.dart';
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
  final emailController = TextEditingController();
  final addressController = TextEditingController();
  final initialBalanceController = TextEditingController(text: '0.00');
  final initialTruckBalanceController = TextEditingController();
  final notesController = TextEditingController();

  // ── Focus nodes ──
  final nameFocus = FocusNode();
  final phoneFocus = FocusNode();
  final addressFocus = FocusNode();
  final initialBalanceFocus = FocusNode();

  String? _selectedCurrency;
  String? get selectedCurrency => _selectedCurrency;
  set selectedCurrency(String? v) => _selectedCurrency = v;

  String _selectedSupplierType = 'shared';
  String get selectedSupplierType => _selectedSupplierType;
  set selectedSupplierType(String v) => _selectedSupplierType = v;
  
  String _initialBalanceDirection = 'CREDIT';
  String get initialBalanceDirection => _initialBalanceDirection;
  set initialBalanceDirection(String v) => _initialBalanceDirection = v;

  // ── Multi-Currency Configuration (Generalized for All Supplier Types) ──
  bool _isMultiCurrency = false;
  bool get isMultiCurrency => _isMultiCurrency;
  set isMultiCurrency(bool v) => _isMultiCurrency = v;

  List<String> _selectedSupportedCurrencies = ['EGP', 'USD', 'EUR'];
  List<String> get selectedSupportedCurrencies => _selectedSupportedCurrencies;
  set selectedSupportedCurrencies(List<String> v) => _selectedSupportedCurrencies = v;

  String _selectedCropCurrency = 'USD';
  String get selectedCropCurrency => _selectedCropCurrency;
  set selectedCropCurrency(String v) => _selectedCropCurrency = v;

  String _selectedPackagingCurrency = 'EGP';
  String get selectedPackagingCurrency => _selectedPackagingCurrency;
  set selectedPackagingCurrency(String v) => _selectedPackagingCurrency = v;

  // ── Multi-Currency Opening Balances Map ──
  final Map<String, CurrencyBalanceFormItem> currencyBalanceItems = {};

  void syncCurrencyBalanceItems() {
    // Remove currencies that are no longer supported
    final toRemove = currencyBalanceItems.keys
        .where((c) => !_selectedSupportedCurrencies.contains(c))
        .toList();
    for (final c in toRemove) {
      currencyBalanceItems[c]?.dispose();
      currencyBalanceItems.remove(c);
    }

    // Add newly supported currencies
    for (final c in _selectedSupportedCurrencies) {
      if (!currencyBalanceItems.containsKey(c)) {
        final item = CurrencyBalanceFormItem(
          currency: c,
          direction: _initialBalanceDirection,
        );
        currencyBalanceItems[c] = item;
        if (c == 'EGP') {
          item.exchangeRateController.text = '1.00';
        } else {
          _fetchRateForFormItem(c);
        }
      }
    }
  }

  Future<void> _fetchRateForFormItem(String currency) async {
    final item = currencyBalanceItems[currency];
    if (item == null || currency == 'EGP') return;
    try {
      final rate = await CurrencyConversionService.instance.getRate(currency);
      if (currencyBalanceItems.containsKey(currency)) {
        item.exchangeRateController.text = rate.toStringAsFixed(2);
      }
    } catch (e) {
      debugPrint('SupplierCubit._fetchRateForFormItem error: $e');
    }
  }

  Future<void> refreshRateForCurrency(String currency) async {
    final item = currencyBalanceItems[currency];
    if (item == null || currency == 'EGP') return;
    item.isFetchingRate = true;
    try {
      CurrencyConversionService.instance.invalidateCache();
      final rate = await CurrencyConversionService.instance.getRate(currency);
      item.exchangeRateController.text = rate.toStringAsFixed(2);
    } catch (e) {
      debugPrint('SupplierCubit.refreshRateForCurrency error: $e');
    } finally {
      item.isFetchingRate = false;
    }
  }

  double get totalMultiCurrencyInitialBalanceEgp {
    double total = 0.0;
    for (final item in currencyBalanceItems.values) {
      total += item.signedAmountInEgp;
    }
    return total;
  }

  void toggleSupportedCurrency(String currency) {
    if (_selectedSupportedCurrencies.contains(currency)) {
      if (_selectedSupportedCurrencies.length > 1) {
        _selectedSupportedCurrencies.remove(currency);
      }
    } else {
      _selectedSupportedCurrencies.add(currency);
    }
    // Auto-adjust default stream currencies if they are no longer in selected list
    if (!_selectedSupportedCurrencies.contains(_selectedCropCurrency) && _selectedSupportedCurrencies.isNotEmpty) {
      _selectedCropCurrency = _selectedSupportedCurrencies.first;
    }
    if (!_selectedSupportedCurrencies.contains(_selectedPackagingCurrency) && _selectedSupportedCurrencies.isNotEmpty) {
      _selectedPackagingCurrency = _selectedSupportedCurrencies.first;
    }
    syncCurrencyBalanceItems();
  }

  late final StreamSubscription<void> _suppliersSub;
  Timer? _debounce;

  SupplierCubit() : super(const SupplierInitial()) {
    _suppliersSub =
        DataChangeEventBus.instance.suppliersStream.listen((_) => refresh());
  }

  /// Refreshes the suppliers list in real-time, preserving any active search query
  Future<void> refresh() async {
    if (_currentQuery.isNotEmpty) {
      await _runSearch(reset: true);
    } else {
      await loadAll(reset: true);
    }
  }

  Future<void> init() async {
    await refresh();
  }

  /// Fetch current exchange rates (EGP = 1.0 baseline).
  Future<Map<String, double>> _fetchRates() async {
    try {
      final svc = CurrencyConversionService.instance;
      final usd = await svc.getRate('USD');
      final eur = await svc.getRate('EUR');
      final gbp = await svc.getRate('GBP');
      return {'EGP': 1.0, 'USD': usd, 'EUR': eur, 'GBP': gbp};
    } catch (_) {
      return {'EGP': 1.0, 'USD': 50.0, 'EUR': 55.0, 'GBP': 65.0};
    }
  }

  // ── Form: Prepare ADD ──

  Future<void> prepareAddForm({String defaultType = 'crop'}) async {
    _clearForm();
    _formState = const SupplierFormState(isEditing: false);
    _selectedCurrency = 'EGP';
    _selectedSupplierType = defaultType;
    _initialBalanceDirection = 'CREDIT';

    // Generalized Multi-Currency:
    // Defaults to false for standard suppliers (single currency EGP),
    // but can be toggled on for any supplier (crop, packaging, shared, etc.)
    _isMultiCurrency = (defaultType == 'shared');
    _selectedSupportedCurrencies = ['EGP', 'USD', 'EUR'];
    _selectedCropCurrency = 'USD';
    _selectedPackagingCurrency = 'EGP';

    syncCurrencyBalanceItems();

    final range = SupplierModel.getCategoryRange(defaultType);
    codeController.text = range.minCode.toString();
    await _generateCode();
  }

  // ── Form: Prepare EDIT ──

  Future<void> prepareEditForm(SupplierModel supplier) async {
    for (final item in currencyBalanceItems.values) {
      item.dispose();
    }
    currencyBalanceItems.clear();

    _formState = SupplierFormState(
      isEditing: true,
      editingSupplier: supplier,
    );
    codeController.text = supplier.supplierCode;
    nameController.text = supplier.name;
    phoneController.text = supplier.phone;
    addressController.text = supplier.address;
    initialBalanceController.text = supplier.initialBalance == 0.0
        ? '0.00'
        : supplier.initialBalance.toString();
    _initialBalanceDirection = supplier.initialBalanceDirection;
    _selectedCurrency = supplier.currency;
    _selectedSupplierType = supplier.supplierType;

    // Generalized multi-currency: load settings for any supplier type
    _isMultiCurrency = supplier.supportsMultiCurrency;
    _selectedSupportedCurrencies = supplier.supportedCurrencies.isNotEmpty
        ? List<String>.from(supplier.supportedCurrencies)
        : (supplier.currency == 'MULTI' ? ['EGP', 'USD', 'EUR'] : [supplier.currency]);
    _selectedCropCurrency = supplier.cropCurrency.isNotEmpty ? supplier.cropCurrency : 'USD';
    _selectedPackagingCurrency = supplier.packagingCurrency.isNotEmpty ? supplier.packagingCurrency : 'EGP';

    if (supplier.initialBalancesByCurrency.isNotEmpty) {
      supplier.initialBalancesByCurrency.forEach((cur, bal) {
        currencyBalanceItems[cur] = CurrencyBalanceFormItem(
          currency: cur,
          amountController: TextEditingController(
            text: bal.amount == 0.0 ? '0.00' : bal.amount.toString(),
          ),
          exchangeRateController: TextEditingController(
            text: cur == 'EGP' ? '1.00' : bal.exchangeRate.toStringAsFixed(2),
          ),
          direction: bal.direction,
        );
      });
    }
    syncCurrencyBalanceItems();
  }

  Future<void> onSupplierTypeChanged(String newType) async {
    _selectedSupplierType = newType;
    // Suggest multi-currency if user switches to shared, but NEVER restrict or disable it for other types
    if (newType == 'shared' && !_formState.isEditing) {
      _isMultiCurrency = true;
      _selectedCurrency = 'MULTI';
      syncCurrencyBalanceItems();
    }
    if (!_formState.isEditing) {
      final range = SupplierModel.getCategoryRange(newType);
      codeController.text = range.minCode.toString();
      await _generateCode();
    }
  }

  Future<void> _generateCode() async {
    try {
      final code = await _dao.generateNextCode(supplierType: _selectedSupplierType);
      codeController.text = code.replaceAll('SUPP-', '');
    } catch (e) {
      debugPrint('SupplierCubit._generateCode error: $e');
      final range = SupplierModel.getCategoryRange(_selectedSupplierType);
      codeController.text = range.minCode.toString();
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
      final results = await Future.wait([
        _dao.getAll(limit: _limit, offset: _offset),
        _fetchRates(),
      ]);
      if (isClosed) return;
      final newItems = results[0] as List<SupplierModel>;
      final rates = results[1] as Map<String, double>;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(SupplierLoaded.fromList(
          suppliers: newItems,
          hasMore: hasMore,
          rates: rates,
        ));
      } else if (currentState is SupplierLoaded) {
        final combinedRates = currentState.exchangeRates;
        emit(currentState.copyWith(
          suppliers: [...currentState.suppliers, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
          exchangeRates: combinedRates,
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

      final results = await Future.wait([
        _dao.search(_currentQuery, limit: _limit, offset: _offset),
        _fetchRates(),
      ]);
      if (isClosed) return;
      final newItems = results[0] as List<SupplierModel>;
      final rates = results[1] as Map<String, double>;
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(SupplierLoaded.fromList(
          suppliers: newItems,
          searchQuery: _currentQuery,
          hasMore: hasMore,
          rates: rates,
        ));
      } else if (currentState is SupplierLoaded) {
        final combinedRates = currentState.exchangeRates;
        emit(currentState.copyWith(
          suppliers: [...currentState.suppliers, ...newItems],
          searchQuery: _currentQuery,
          hasMore: hasMore,
          isFetchingMore: false,
          exchangeRates: combinedRates,
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

    if (_formState.isSaving) return false;

    final codeValidationError = SupplierModel.validateSupplierCode(
      codeController.text.trim(),
      _selectedSupplierType,
    );
    if (codeValidationError != null) {
      debugPrint('SupplierCubit.save validation error: $codeValidationError');
      return false;
    }

    final nameValidationError = SupplierModel.validateSupplierName(
      nameController.text.trim(),
    );
    if (nameValidationError != null) {
      debugPrint('SupplierCubit.save validation error: $nameValidationError');
      return false;
    }

    _formState = _formState.copyWith(isSaving: true);
    emit(_formState);

    try {
      final initialBal = double.tryParse(initialBalanceController.text.trim()) ?? 0.0;
      final effectiveCurrency = _isMultiCurrency ? 'MULTI' : (_selectedCurrency ?? 'EGP');

      Map<String, SupplierCurrencyBalance> initialBalances = {};
      double aggregateInitialBal = initialBal;
      String aggregateInitialDir = _initialBalanceDirection;

      if (_isMultiCurrency) {
        for (final entry in currencyBalanceItems.entries) {
          initialBalances[entry.key] = entry.value.toBalanceModel();
        }
        final netEgp = totalMultiCurrencyInitialBalanceEgp;
        aggregateInitialBal = netEgp.abs();
        aggregateInitialDir = netEgp >= 0 ? 'CREDIT' : 'DEBIT';
      } else {
        initialBalances[effectiveCurrency] = SupplierCurrencyBalance(
          currency: effectiveCurrency,
          amount: initialBal,
          direction: _initialBalanceDirection,
          exchangeRate: 1.0,
        );
      }

      int? targetAccountId = _formState.editingSupplier?.accountId;
      if (targetAccountId == null) {
        targetAccountId = await _dao.resolveMasterAccountId(
          _selectedSupplierType,
          code: codeController.text.trim(),
        );
      }

      final supplierData = SupplierModel(
        id: _formState.editingSupplier?.id,
        accountId: targetAccountId,
        supplierCode: codeController.text.trim(),
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
        address: addressController.text.trim(),
        supplierType: _selectedSupplierType,
        initialBalance: aggregateInitialBal,
        initialBalanceDirection: aggregateInitialDir,
        currency: effectiveCurrency,
        isMultiCurrency: _isMultiCurrency,
        supportedCurrencies: _isMultiCurrency ? _selectedSupportedCurrencies : [effectiveCurrency],
        cropCurrency: _selectedCropCurrency,
        packagingCurrency: _selectedPackagingCurrency,
        initialBalancesByCurrency: initialBalances,
        outstandingBalance: _formState.editingSupplier == null
            ? 0.0
            : (_formState.editingSupplier!.outstandingBalance + (aggregateInitialBal - _formState.editingSupplier!.initialBalance)),
      );

      debugPrint('SupplierCubit: supplierData = ${supplierData.toInsertMap()}');

      if (_selectedSupplierType == 'transport') {
        final transportData = TransportSupplierModel(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          email: emailController.text.trim(),
          initialBalance: aggregateInitialBal,
          initialBalanceDirection: aggregateInitialDir,
          initialTruckBalance:
              double.tryParse(initialTruckBalanceController.text.trim()) ?? 0.0,
          notes: notesController.text.trim().isNotEmpty
              ? notesController.text.trim()
              : null,
          createdAt: DateTime.now().toIso8601String(),
        );
        await TransportSupplierDao().create(transportData);
        DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      } else {
        if (_formState.editingSupplier == null) {
          await _dao.insert(supplierData);
          debugPrint('SupplierCubit: inserted supplier code=${supplierData.supplierCode}');
        } else {
          await _dao.update(supplierData);
          debugPrint('SupplierCubit: updated supplier code=${supplierData.supplierCode}');
        }
      }

      await loadAll(reset: true);
      if (isClosed) return true;
      DataChangeEventBus.instance.notifySuppliersChanged();
      return true;
    } catch (e) {
      debugPrint('SupplierCubit.save error: $e');
      return false;
    } finally {
      if (!isClosed) {
        _formState = _formState.copyWith(isSaving: false);
        emit(_formState);
      }
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
    for (final item in currencyBalanceItems.values) {
      item.dispose();
    }
    currencyBalanceItems.clear();

    codeController.clear();
    nameController.clear();
    phoneController.clear();
    emailController.clear();
    addressController.clear();
    initialBalanceController.text = '0.00';
    initialTruckBalanceController.clear();
    notesController.clear();
    _selectedCurrency = 'EGP';
    _selectedSupplierType = 'crop';
    _isMultiCurrency = false;
    _selectedSupportedCurrencies = ['EGP', 'USD', 'EUR'];
    _selectedCropCurrency = 'USD';
    _selectedPackagingCurrency = 'EGP';
    _formState = _formState.copyWith(clearEditingSupplier: true);
  }

  @override
  Future<void> close() {
    for (final item in currencyBalanceItems.values) {
      item.dispose();
    }
    currencyBalanceItems.clear();

    _suppliersSub.cancel();
    _debounce?.cancel();
    codeController.dispose();
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    initialBalanceController.dispose();
    initialTruckBalanceController.dispose();
    notesController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    addressFocus.dispose();
    initialBalanceFocus.dispose();
    return super.close();
  }
}

/// Helper model managing live text controllers and exchange rate syncing for a single currency
class CurrencyBalanceFormItem {
  final String currency;
  final TextEditingController amountController;
  final TextEditingController exchangeRateController;
  String direction; // 'CREDIT' or 'DEBIT'
  bool isFetchingRate;

  CurrencyBalanceFormItem({
    required this.currency,
    TextEditingController? amountController,
    TextEditingController? exchangeRateController,
    this.direction = 'CREDIT',
    this.isFetchingRate = false,
  })  : amountController = amountController ?? TextEditingController(text: '0.00'),
        exchangeRateController = exchangeRateController ??
            TextEditingController(text: currency == 'EGP' ? '1.00' : '50.00');

  double get amount => double.tryParse(amountController.text.trim()) ?? 0.0;

  double get exchangeRate {
    if (currency == 'EGP') return 1.0;
    final parsed = double.tryParse(exchangeRateController.text.trim());
    return (parsed != null && parsed > 0) ? parsed : 1.0;
  }

  double get amountInEgp =>
      CurrencyConversionService.instance.toBase(amount, currency, exchangeRate);

  double get signedAmountInEgp =>
      direction == 'CREDIT' ? amountInEgp : -amountInEgp;

  SupplierCurrencyBalance toBalanceModel() {
    return SupplierCurrencyBalance(
      currency: currency,
      amount: amount,
      direction: direction,
      exchangeRate: exchangeRate,
    );
  }

  void dispose() {
    amountController.dispose();
    exchangeRateController.dispose();
  }
}