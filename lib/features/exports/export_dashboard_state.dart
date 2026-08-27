import 'package:equatable/equatable.dart';
import '../../data/models/export_invoice_model.dart';

class MonthlyBucket {
  final int year;
  final int month;
  final int count;
  const MonthlyBucket({required this.year, required this.month, required this.count});

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}: $count';
}

abstract class ExportDashboardState extends Equatable {
  const ExportDashboardState();
  @override
  List<Object?> get props => [];
}

class ExportDashboardInitial extends ExportDashboardState {
  const ExportDashboardInitial();
}

class ExportDashboardLoading extends ExportDashboardState {
  const ExportDashboardLoading();
}

class ExportDashboardLoaded extends ExportDashboardState {
  final int totalCartons;
  final int totalPallets;
  final double totalNetWeight;
  final double totalGrossWeight;
  final int seaCount;
  final int airCount;
  final int totalInvoices;
  final List<ExportInvoiceModel> recentInvoices;
  final List<MonthlyBucket> monthlyData;

  const ExportDashboardLoaded({
    required this.totalCartons,
    required this.totalPallets,
    required this.totalNetWeight,
    required this.totalGrossWeight,
    required this.seaCount,
    required this.airCount,
    required this.totalInvoices,
    required this.recentInvoices,
    required this.monthlyData,
  });

  @override
  List<Object?> get props => [
    totalCartons, totalPallets, totalNetWeight, totalGrossWeight,
    seaCount, airCount, totalInvoices, recentInvoices, monthlyData,
  ];
}

class ExportDashboardError extends ExportDashboardState {
  final String message;
  const ExportDashboardError(this.message);
  @override
  List<Object?> get props => [message];
}
