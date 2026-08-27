import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/export_invoice_dao.dart';
import '../../data/models/export_invoice_model.dart';
import 'export_dashboard_state.dart';

class ExportDashboardCubit extends Cubit<ExportDashboardState> {
  final ExportInvoiceDao _dao = ExportInvoiceDao();

  ExportDashboardCubit() : super(const ExportDashboardInitial());

  Future<void> load() async {
    emit(const ExportDashboardLoading());
    try {
      final results = await Future.wait([
        _dao.getAggregates(),
        _dao.getAllUnpaginated(),
        _dao.getRecent(5),
      ]);
      final agg = results[0] as Map<String, dynamic>;
      final all = results[1] as List<ExportInvoiceModel>;
      final recent = results[2] as List<ExportInvoiceModel>;

      final monthly = _computeMonthly(all);

      emit(ExportDashboardLoaded(
        totalCartons: agg['totalCartons'] as int,
        totalPallets: agg['totalPallets'] as int,
        totalNetWeight: (agg['totalNetWeight'] as num).toDouble(),
        totalGrossWeight: (agg['totalGrossWeight'] as num).toDouble(),
        seaCount: agg['seaCount'] as int,
        airCount: agg['airCount'] as int,
        totalInvoices: agg['totalInvoices'] as int,
        recentInvoices: recent,
        monthlyData: monthly,
      ));
    } catch (e) {
      emit(ExportDashboardError('فشل تحميل البيانات: $e'));
    }
  }

  List<MonthlyBucket> _computeMonthly(List<ExportInvoiceModel> invoices) {
    final map = <int, int>{};
    for (final inv in invoices) {
      final key = inv.date.year * 100 + inv.date.month;
      map[key] = (map[key] ?? 0) + 1;
    }
    final sorted = map.keys.toList()..sort();
    return sorted.map((k) {
      final year = k ~/ 100;
      final month = k % 100;
      return MonthlyBucket(year: year, month: month, count: map[k]!);
    }).toList();
  }
}
