import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/shipment_cost_item_dao.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../core/data_change_event_bus.dart';
import 'clearing_agent_state.dart';

class ClearingAgentCubit extends Cubit<ClearingAgentState> {
  final ClearingAgentDao _dao = ClearingAgentDao();

  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';
  String _currentTypeFilter = 'all';

  ClearingAgentFormState _formState = const ClearingAgentFormState();
  ClearingAgentFormState get formState => _formState;

  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final cityController = TextEditingController();
  final countryController = TextEditingController();
  final gmailController = TextEditingController();
  final contactNameController = TextEditingController();
  final contactPhoneController = TextEditingController();
  final contactEmailController = TextEditingController();
  final initialBalanceController = TextEditingController();

  String brokerType = 'بحري';
  String? selectedCurrency;
  String initialBalanceDirection = 'CREDIT';

  final nameFocus = FocusNode();
  final phoneFocus = FocusNode();
  final cityFocus = FocusNode();
  final countryFocus = FocusNode();
  final gmailFocus = FocusNode();
  final contactNameFocus = FocusNode();
  final contactPhoneFocus = FocusNode();
  final contactEmailFocus = FocusNode();

  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> get addresses => List.unmodifiable(_addresses);

  late final StreamSubscription<void> _sub;
  Timer? _debounce;

  ClearingAgentCubit() : super(const ClearingAgentInitial()) {
    _sub = DataChangeEventBus.instance.clearingAgentsStream.listen((_) => loadAll(reset: true));
  }

  Future<void> init() async => await loadAll(reset: true);

  Future<void> prepareAddForm() async {
    _formState = const ClearingAgentFormState(isEditing: false);
    _clearForm();
    initialBalanceDirection = 'CREDIT';
    codeController.text = await _dao.generateNextCode();
  }

  Future<void> prepareEditForm(ClearingAgentModel agent) async {
    _formState = ClearingAgentFormState(isEditing: true, editingAgent: agent);
    codeController.text = agent.code;
    nameController.text = agent.name;
    phoneController.text = agent.phone;
    cityController.text = agent.city;
    countryController.text = agent.country;
    gmailController.text = agent.gmail;
    brokerType = agent.brokerType;
    selectedCurrency = agent.currency;
    contactNameController.text = agent.contactPersonName;
    contactPhoneController.text = agent.contactPersonPhone;
    contactEmailController.text = agent.contactPersonEmail;
    initialBalanceDirection = agent.initialBalanceDirection;
    initialBalanceController.text = agent.initialBalance == 0.0 ? '' : agent.initialBalance.toString();
    _addresses = agent.addresses.map((a) => Map<String, dynamic>.from(a)).toList();
  }

  // ── Load ──

  Future<void> loadAll({bool reset = false}) async {
    if (isClosed) return;
    if (reset) {
      _offset = 0;
      _currentQuery = '';
      emit(const ClearingAgentLoading());
    }

    final currentState = state;
    if (currentState is ClearingAgentLoaded && !currentState.hasMore && !reset) return;

    try {
      final newItems = await _dao.getAll(limit: _limit, offset: _offset);
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(ClearingAgentLoaded(agents: newItems, hasMore: hasMore));
      } else if (currentState is ClearingAgentLoaded) {
        emit(currentState.copyWith(
          agents: [...currentState.agents, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(ClearingAgentError(message: 'حدث خطأ أثناء تحميل البيانات: $e'));
    }
  }

  // ── Search ──

  void onSearchChanged(String query) {
    _currentQuery = query.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(reset: true));
  }

  // ── Type Filter ──

  void onTypeFilterChanged(String type) {
    _currentTypeFilter = type;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () => _runSearch(reset: true));
  }

  Future<void> _runSearch({bool reset = false}) async {
    if (reset) _offset = 0;

    final currentState = state;
    if (currentState is ClearingAgentLoaded && !currentState.hasMore && !reset) return;

    try {
      if (_currentQuery.isEmpty && _currentTypeFilter == 'all') {
        await loadAll(reset: reset);
        return;
      }

      final newItems = await _dao.search(
        _currentQuery,
        typeFilter: _currentTypeFilter == 'all' ? null : _currentTypeFilter,
        limit: _limit,
        offset: _offset,
      );
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(ClearingAgentLoaded(agents: newItems, searchQuery: _currentQuery, typeFilter: _currentTypeFilter, hasMore: hasMore));
      } else if (currentState is ClearingAgentLoaded) {
        emit(currentState.copyWith(
          agents: [...currentState.agents, ...newItems],
          searchQuery: _currentQuery,
          typeFilter: _currentTypeFilter,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(ClearingAgentError(message: 'حدث خطأ أثناء البحث: $e'));
    }
  }

  Future<void> fetchMore() async {
    final currentState = state;
    if (currentState is! ClearingAgentLoaded) return;
    if (currentState.isFetchingMore || !currentState.hasMore) return;
    emit(currentState.copyWith(isFetchingMore: true));
    _currentQuery.isEmpty ? await loadAll() : await _runSearch();
  }

  // ── Address ──

  void setSingleAddress(String text) {
    if (text.isEmpty) {
      _addresses = [];
    } else {
      _addresses = [{'address_line_1': text, 'city': '', 'country': '', 'type': 'quick'}];
    }
    emit(_formState.copyWith(addressesVersion: DateTime.now().millisecondsSinceEpoch));
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
      if (_formState.editingAgent == null) {
        final newAgent = ClearingAgentModel(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          city: cityController.text.trim(),
          country: countryController.text.trim(),
          gmail: gmailController.text.trim(),
          brokerType: brokerType,
          contactPersonName: contactNameController.text.trim(),
          contactPersonPhone: contactPhoneController.text.trim(),
          contactPersonEmail: contactEmailController.text.trim(),
          addresses: List.from(_addresses),
          initialBalance: double.tryParse(initialBalanceController.text.trim()) ?? 0.0,
          initialBalanceDirection: initialBalanceDirection,
          balance: double.tryParse(initialBalanceController.text.trim()) ?? 0.0,
          currency: selectedCurrency!,
          createdAt: now,
        );
        await _dao.insert(newAgent);
      } else {
        final updated = _formState.editingAgent!.copyWith(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          city: cityController.text.trim(),
          country: countryController.text.trim(),
          gmail: gmailController.text.trim(),
          brokerType: brokerType,
          contactPersonName: contactNameController.text.trim(),
          contactPersonPhone: contactPhoneController.text.trim(),
          contactPersonEmail: contactEmailController.text.trim(),
          addresses: List.from(_addresses),
          initialBalance: double.tryParse(initialBalanceController.text.trim()) ?? 0.0,
          initialBalanceDirection: initialBalanceDirection,
        );
        await _dao.update(updated);
      }

      await loadAll(reset: true);
      await ShipmentCostItemDao().updateVendorBalances();
      DataChangeEventBus.instance.notifyClearingAgentsChanged();
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return true;
    } catch (e) {
      debugPrint('ClearingAgentCubit.save error: $e');
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return false;
    }
  }

  // ── Delete ──

  Future<bool> deleteAgent(ClearingAgentModel agent) async {
    try {
      await _dao.delete(agent.id!);
      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyClearingAgentsChanged();
      return true;
    } catch (e) {
      debugPrint('ClearingAgentCubit.delete error: $e');
      return false;
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
    contactNameController.clear();
    contactPhoneController.clear();
    contactEmailController.clear();
    initialBalanceController.clear();
    brokerType = 'بحري';
    selectedCurrency = null;
    _addresses = [];
    _formState = _formState.copyWith(clearEditingAgent: true);
  }

  @override
  Future<void> close() {
    _sub.cancel();
    _debounce?.cancel();
    codeController.dispose();
    nameController.dispose();
    phoneController.dispose();
    cityController.dispose();
    countryController.dispose();
    gmailController.dispose();
    contactNameController.dispose();
    contactPhoneController.dispose();
    contactEmailController.dispose();
    initialBalanceController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    cityFocus.dispose();
    countryFocus.dispose();
    gmailFocus.dispose();
    contactNameFocus.dispose();
    contactPhoneFocus.dispose();
    contactEmailFocus.dispose();
    return super.close();
  }
}
