import 'package:equatable/equatable.dart';
import '../../data/models/station_model.dart';
import '../../data/models/warehouse_movement_model.dart';

abstract class WarehouseTrackingState extends Equatable {
  const WarehouseTrackingState();
  @override
  List<Object?> get props => [];
}

class WarehouseTrackingInitial extends WarehouseTrackingState {
  const WarehouseTrackingInitial();
}

class WarehouseTrackingLoading extends WarehouseTrackingState {
  const WarehouseTrackingLoading();
}

class WarehouseTrackingLoaded extends WarehouseTrackingState {
  final List<StationModel> stations;
  final Map<String, Map<String, int>> stationStats;
  final Map<String, List<Map<String, dynamic>>> stationProducts;
  final Map<String, Map<String, double>> stationValues;

  const WarehouseTrackingLoaded({
    required this.stations,
    required this.stationStats,
    this.stationProducts = const {},
    this.stationValues = const {},
  });

  @override
  List<Object?> get props => [stations, stationStats, stationProducts, stationValues];
}

class WarehouseTrackingDetailLoading extends WarehouseTrackingState {
  const WarehouseTrackingDetailLoading();
}

class WarehouseTrackingDetailLoaded extends WarehouseTrackingState {
  final StationModel station;
  final List<WarehouseMovementModel> movements;
  final DateTime? fromDate;
  final DateTime? toDate;

  const WarehouseTrackingDetailLoaded({
    required this.station,
    required this.movements,
    this.fromDate,
    this.toDate,
  });

  @override
  List<Object?> get props => [station, movements, fromDate, toDate];
}

class WarehouseTrackingError extends WarehouseTrackingState {
  final String message;
  const WarehouseTrackingError({required this.message});
  @override
  List<Object?> get props => [message];
}
