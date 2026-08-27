import 'package:equatable/equatable.dart';

abstract class ReportState extends Equatable {
  const ReportState();

  @override
  List<Object?> get props => [];
}

class ReportInitial extends ReportState {
  const ReportInitial();
}

class ReportLoading extends ReportState {
  const ReportLoading();
}

class ReportLoaded extends ReportState {
  final double filteredIncome;
  final String topSupplier;
  final String topCustomer;
  final String topItem;
  final String biggestDebtor;
  final String biggestCreditor;
  final List<Map<String, dynamic>> priceAlerts;
  final DateTime fromDate;
  final DateTime toDate;

  const ReportLoaded({
    required this.filteredIncome,
    required this.topSupplier,
    required this.topCustomer,
    required this.topItem,
    required this.biggestDebtor,
    required this.biggestCreditor,
    required this.priceAlerts,
    required this.fromDate,
    required this.toDate,
  });

  ReportLoaded copyWith({
    double? filteredIncome,
    String? topSupplier,
    String? topCustomer,
    String? topItem,
    String? biggestDebtor,
    String? biggestCreditor,
    List<Map<String, dynamic>>? priceAlerts,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return ReportLoaded(
      filteredIncome: filteredIncome ?? this.filteredIncome,
      topSupplier: topSupplier ?? this.topSupplier,
      topCustomer: topCustomer ?? this.topCustomer,
      topItem: topItem ?? this.topItem,
      biggestDebtor: biggestDebtor ?? this.biggestDebtor,
      biggestCreditor: biggestCreditor ?? this.biggestCreditor,
      priceAlerts: priceAlerts ?? this.priceAlerts,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
    );
  }

  @override
  List<Object?> get props => [
        filteredIncome,
        topSupplier,
        topCustomer,
        topItem,
        biggestDebtor,
        biggestCreditor,
        priceAlerts,
        fromDate,
        toDate,
      ];
}

class ReportError extends ReportState {
  final String message;

  const ReportError({required this.message});

  @override
  List<Object?> get props => [message];
}
