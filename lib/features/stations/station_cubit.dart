import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/station_dao.dart';
import '../../data/models/station_model.dart';
import '../../core/data_change_event_bus.dart';
import 'station_state.dart';

class StationCubit extends Cubit<StationState> {
  final StationDao _dao = StationDao();

  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';

  StationFormState _formState = const StationFormState();
  StationFormState get formState => _formState;

  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  String _stationType = 'sub';
  String get stationType => _stationType;

  late final StreamSubscription<void> _stationsSub;
  Timer? _debounce;

  StationCubit() : super(const StationInitial()) {
    _stationsSub =
        DataChangeEventBus.instance.stationsStream.listen((_) => loadAll(reset: true));
  }

  Future<void> init() async {
    await loadAll(reset: true);
  }

  void setStationType(String type) {
    _stationType = type;
  }

  Future<void> prepareAddForm() async {
    _clearForm();
    _stationType = 'sub';
    try {
      final code = await _dao.generateNextCode();
      codeController.text = code;
    } catch (e) {
      codeController.text = StationModel.minCode.toString();
    }
    
    _formState = const StationFormState(isEditing: false);
  }

  Future<void> prepareEditForm(StationModel station) async {
    codeController.text = station.code;
    nameController.text = station.name;
    _stationType = station.type;
    
    _formState = StationFormState(isEditing: true, editingStation: station);
  }

  Future<void> loadAll({bool reset = false}) async {
    if (isClosed) return;
    if (reset) {
      _offset = 0;
      _currentQuery = '';
      emit(const StationLoading());
    }

    final currentState = state;
    if (currentState is StationLoaded && !currentState.hasMore && !reset) return;

    try {
      final newItems = await _dao.getAll(limit: _limit, offset: _offset);
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (isClosed) return;
      if (reset) {
        emit(StationLoaded(stations: newItems, hasMore: hasMore));
      } else if (currentState is StationLoaded) {
        emit(currentState.copyWith(
          stations: [...currentState.stations, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      if (!isClosed) emit(StationError(message: 'حدث خطأ أثناء تحميل البيانات: $e'));
    }
  }

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
    if (currentState is StationLoaded && !currentState.hasMore && !reset) return;

    try {
      if (_currentQuery.isEmpty) {
        await loadAll(reset: reset);
        return;
      }

      final newItems = await _dao.search(_currentQuery, limit: _limit, offset: _offset);
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        emit(StationLoaded(
          stations: newItems,
          searchQuery: _currentQuery,
          hasMore: hasMore,
        ));
      } else if (currentState is StationLoaded) {
        emit(currentState.copyWith(
          stations: [...currentState.stations, ...newItems],
          searchQuery: _currentQuery,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(StationError(message: 'حدث خطأ أثناء البحث: $e'));
    }
  }

  Future<void> fetchMore() async {
    final currentState = state;
    if (currentState is! StationLoaded) return;
    if (currentState.isFetchingMore || !currentState.hasMore) return;

    emit(currentState.copyWith(isFetchingMore: true));

    if (_currentQuery.isEmpty) {
      await loadAll();
    } else {
      await _runSearch();
    }
  }

  Future<bool> save() async {
    if (!formKey.currentState!.validate()) return false;

    _formState = _formState.copyWith(isSaving: true);
    emit(_formState);

    try {
      final now = DateTime.now().toIso8601String();

      if (_formState.editingStation == null) {
        final station = StationModel(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          type: _stationType,
          createdAt: now,
        );
        await _dao.insert(station);
      } else {
        final updated = _formState.editingStation!.copyWith(
          code: codeController.text.trim(),
          name: nameController.text.trim(),
          type: _stationType,
        );
        await _dao.update(updated);
      }

      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyStationsChanged();
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return true;
    } catch (e) {
      debugPrint('StationCubit.save error: $e');
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return false;
    }
  }

  Future<bool> deleteStation(StationModel station) async {
    try {
      await _dao.delete(station.id!);
      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyStationsChanged();
      return true;
    } catch (e) {
      debugPrint('StationCubit.delete error: $e');
      return false;
    }
  }

  void _clearForm() {
    codeController.clear();
    nameController.clear();
    _stationType = 'sub';
    _formState = _formState.copyWith(clearEditingStation: true);
  }

  @override
  Future<void> close() {
    _stationsSub.cancel();
    _debounce?.cancel();
    codeController.dispose();
    nameController.dispose();
    return super.close();
  }
}