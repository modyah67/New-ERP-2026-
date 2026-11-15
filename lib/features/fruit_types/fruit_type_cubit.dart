import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/fruit_type_model.dart';
import '../../data/models/fruit_type_group_model.dart';
import 'fruit_type_state.dart';

class FruitTypeCubit extends Cubit<FruitTypeState> {
  final FruitTypeDao _dao = FruitTypeDao();

  StreamSubscription<void>? _stationsSub;
  StreamSubscription<void>? _cropPurchasesSub;
  StreamSubscription<void>? _itemsSub;
  Timer? _debounceLoad;

  FruitTypeCubit() : super(const FruitTypeInitial()) {
    _stationsSub = DataChangeEventBus.instance.stationsStream.listen((_) => _debouncedLoad());
    _cropPurchasesSub = DataChangeEventBus.instance.cropPurchasesStream.listen((_) => _debouncedLoad());
    _itemsSub = DataChangeEventBus.instance.itemsStream.listen((_) => _debouncedLoad());
  }

  void _debouncedLoad() {
    _debounceLoad?.cancel();
    _debounceLoad = Timer(const Duration(milliseconds: 300), () {
      if (!isClosed) loadAll();
    });
  }

  Future<void> loadAll() async {
    if (isClosed) return;
    final currentState = state;
    final String currentQuery = currentState is FruitTypeLoaded ? currentState.searchQuery : '';
    final String? currentMode = currentState is FruitTypeLoaded ? currentState.selectedPurchaseMode : null;

    if (currentState is! FruitTypeLoaded) {
      emit(const FruitTypeLoading());
    }

    try {
      final results = await Future.wait([
        _dao.getAllWithPrices(),
        _dao.getWarehouseDistribution(),
        _dao.getStockByFruitTypeId(),
      ]);
      if (isClosed) return;

      final items = results[0] as List<FruitTypeModel>;
      final warehouseDist = results[1] as Map<String, List<Map<String, dynamic>>>;
      final stockByTypeId = results[2] as Map<int, double>;

      for (final item in items) {
        final idInt = int.tryParse(item.id ?? '');
        final directStock = idInt != null ? stockByTypeId[idInt] : null;
        if (directStock != null) {
          item.totalStockQuantity = directStock;
        } else {
          List<Map<String, dynamic>> distList = [];
          if (item.id != null && warehouseDist.containsKey('fruit_${item.id}')) {
            distList = warehouseDist['fruit_${item.id}']!;
          } else if (item.name.isNotEmpty && warehouseDist.containsKey(item.name)) {
            distList = warehouseDist[item.name]!;
          } else {
            final cleanName = item.name.trim().toLowerCase();
            if (cleanName.isNotEmpty && warehouseDist.containsKey(cleanName)) {
              distList = warehouseDist[cleanName]!;
            }
          }

          distList = distList.toSet().toList();

          if (distList.isNotEmpty) {
            final sumQty = distList.fold<double>(
              0.0,
              (s, d) => s + ((d['quantity'] as num?)?.toDouble() ?? 0.0),
            );
            item.totalStockQuantity = sumQty;
          } else {
            item.totalStockQuantity = 0.0;
          }
        }
      }

      final groups = FruitTypeGroupModel.groupFromItems(items);
      final filtered = _filterGroups(groups, currentQuery, currentMode);

      emit(FruitTypeLoaded(
        items: items,
        groups: groups,
        filteredGroups: filtered,
        warehouseDistribution: warehouseDist,
        searchQuery: currentQuery,
        selectedPurchaseMode: currentMode,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(FruitTypeError(message: 'خطأ في تحميل أصناف الفاكهة: $e'));
    }
  }

  void onSearchChanged(String query) {
    final currentState = state;
    if (currentState is! FruitTypeLoaded) return;
    final trimmed = query.trim();
    final filtered = _filterGroups(currentState.groups, trimmed, currentState.selectedPurchaseMode);
    emit(currentState.copyWith(searchQuery: trimmed, filteredGroups: filtered));
  }

  void onPurchaseModeSelected(String? mode) {
    final currentState = state;
    if (currentState is! FruitTypeLoaded) return;
    final filtered = _filterGroups(currentState.groups, currentState.searchQuery, mode);
    emit(currentState.copyWith(
      selectedPurchaseMode: mode,
      clearSelectedPurchaseMode: mode == null,
      filteredGroups: filtered,
    ));
  }

  static List<FruitTypeGroupModel> _filterGroups(
    List<FruitTypeGroupModel> groups,
    String search,
    String? mode,
  ) {
    return groups.where((group) {
      // 1. Search filter
      if (search.isNotEmpty) {
        final q = search.toLowerCase();
        final matchBaseName = group.baseName.toLowerCase().contains(q);
        final matchWeightCode = group.weightItem?.code.toLowerCase().contains(q) ?? false;
        final matchCartonCode = group.cartonItem?.code.toLowerCase().contains(q) ?? false;
        final matchOtherName = group.otherItems.any((i) => i.name.toLowerCase().contains(q) || i.code.toLowerCase().contains(q));

        if (!matchBaseName && !matchWeightCode && !matchCartonCode && !matchOtherName) {
          return false;
        }
      }

      // 2. Mode filter ('weight', 'carton', 'shared', or null for all)
      if (mode != null) {
        if (mode == 'shared') {
          if (!group.isDualMode) return false;
        } else if (mode == 'weight') {
          if (!group.hasWeight) return false;
        } else if (mode == 'carton') {
          if (!group.hasCarton) return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Future<void> close() {
    _debounceLoad?.cancel();
    _stationsSub?.cancel();
    _cropPurchasesSub?.cancel();
    _itemsSub?.cancel();
    return super.close();
  }
}
