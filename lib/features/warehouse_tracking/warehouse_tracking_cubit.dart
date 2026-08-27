import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/station_dao.dart';
import '../../data/dao/warehouse_tracking_dao.dart';
import '../../data/models/station_model.dart';
import 'warehouse_tracking_state.dart';

class WarehouseTrackingCubit extends Cubit<WarehouseTrackingState> {
  final StationDao _stationDao = StationDao();
  final WarehouseTrackingDao _trackingDao = WarehouseTrackingDao();

  List<StationModel> _stations = [];
  Map<String, Map<String, int>> _stationStats = {};
  Map<String, List<Map<String, dynamic>>> _stationProducts = {};
  StreamSubscription<void>? _sub;

  WarehouseTrackingCubit() : super(const WarehouseTrackingInitial()) {
    _sub = DataChangeEventBus.instance.stationsStream
        .listen((_) => loadStations());
  }

  Future<void> init() async => await loadStations();

  Future<void> loadStations() async {
    if (isClosed) return;
    emit(const WarehouseTrackingLoading());
    try {
      // 1. Fetch stations + stats + products + values in parallel
      final results = await Future.wait([
        _stationDao.getAll(limit: 100),
        _trackingDao.getAllStationStats(),
        _trackingDao.getAllStationProducts(),
        _trackingDao.getAllStationValues(),
      ]);

      _stations = results[0] as List<StationModel>;
      _stationStats = results[1] as Map<String, Map<String, int>>;
      _stationProducts = results[2] as Map<String, List<Map<String, dynamic>>>;
      final stationValues = results[3] as Map<String, Map<String, double>>;

      if (!isClosed) {
        emit(WarehouseTrackingLoaded(
          stations: _stations,
          stationStats: _stationStats,
          stationProducts: _stationProducts,
          stationValues: stationValues,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(WarehouseTrackingError(message: 'حدث خطأ: $e'));
      }
    }
  }

  Future<void> loadStationDetail(StationModel station) async {
    if (isClosed) return;
    emit(const WarehouseTrackingDetailLoading());
    try {
      final movements = await _trackingDao.getMovementsForStation(
        station.id!,
      );
      if (!isClosed) {
        emit(WarehouseTrackingDetailLoaded(
          station: station,
          movements: movements,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(WarehouseTrackingError(message: 'حدث خطأ: $e'));
      }
    }
  }

  Future<void> filterByDate(
      StationModel station, DateTime? fromDate, DateTime? toDate) async {
    if (isClosed) return;
    emit(const WarehouseTrackingDetailLoading());
    try {
      final movements = await _trackingDao.getMovementsForStation(
        station.id!,
        fromDate: fromDate,
        toDate: toDate,
      );
      if (!isClosed) {
        emit(WarehouseTrackingDetailLoaded(
          station: station,
          movements: movements,
          fromDate: fromDate,
          toDate: toDate,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(WarehouseTrackingError(message: 'حدث خطأ: $e'));
      }
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
