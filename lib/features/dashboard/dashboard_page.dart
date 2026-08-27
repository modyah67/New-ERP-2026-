import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/dao/export_invoice_dao.dart';
import '../../data/dao/export_shipment_dao.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _dao = ExportInvoiceDao();
  final _shipmentDao = ExportShipmentDao();
  bool _loading = true;
  double _totalRevenue = 0;
  double _totalCost = 0;
  double _totalProfit = 0;
  List<String> _sortedMonths = [];
  Map<String, double> _monthlyProfit = {};
  int _invoiceCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _dao.getFinancialAggregates(),
        _shipmentDao.getProfitSummary(),
      ]);
      final data = results[0] as Map<String, dynamic>;
      final profitSummary = results[1] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _totalRevenue = (data['totalRevenue'] as num?)?.toDouble() ?? 0;
        _totalCost = (data['totalCost'] as num?)?.toDouble() ?? 0;
        _totalProfit = (profitSummary['net_profit_egp'] as num?)?.toDouble() ?? 0;
        _sortedMonths = List<String>.from(data['sortedMonths'] as List);
        _monthlyProfit = Map<String, double>.from(data['monthlyProfit'] as Map);
        _invoiceCount = (data['invoiceCount'] as int?) ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _formatCurrency(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}م';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(1)}أ';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildKpiGrid(),
          const SizedBox(height: 24),
          _buildChartSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppTheme.neonCyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.25)),
          ),
          child: const Icon(Icons.dashboard_rounded, color: AppTheme.neonCyan, size: 24),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('لوحة البيانات المالية', style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold,
                color: Colors.white, fontFamily: 'Cairo')),
            Text('$_invoiceCount فاتورة تصدير', style: const TextStyle(
                color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
          onPressed: _loading ? null : _load,
          tooltip: 'تحديث',
        ),
      ],
    );
  }

  Widget _buildKpiGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: wide ? (constraints.maxWidth - 32) / 3 : constraints.maxWidth,
              child: _kpiCard(
                title: 'إجمالي الإيرادات الموحدة',
                value: _totalRevenue,
                icon: Icons.trending_up_rounded,
                color: AppTheme.neonCyan,
                prefix: 'ج.م ',
              ),
            ),
            SizedBox(
              width: wide ? (constraints.maxWidth - 32) / 3 : constraints.maxWidth,
              child: _kpiCard(
                title: 'إجمالي تكاليف التعبئة والشحن',
                value: _totalCost,
                icon: Icons.account_balance_wallet_outlined,
                color: AppTheme.warning,
                prefix: 'ج.م ',
              ),
            ),
            SizedBox(
              width: wide ? (constraints.maxWidth - 32) / 3 : constraints.maxWidth,
              child: _kpiCard(
                title: 'صافي أرباح الشركة الصافية',
                value: _totalProfit,
                icon: Icons.monetization_on_rounded,
                color: AppTheme.emerald,
                prefix: 'ج.م ',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
    required String prefix,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Text('EGP', style: TextStyle(
                      color: color.withValues(alpha: 0.6), fontSize: 11,
                      fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                ],
              ),
              const SizedBox(height: 16),
              Text('$prefix${_formatCurrency(value)}', style: TextStyle(
                  color: color == AppTheme.emerald
                      ? const Color(0xFF00E676)
                      : Colors.white,
                  fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12,
                  fontFamily: 'Cairo')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.04),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.neonCyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.show_chart_rounded,
                        color: AppTheme.neonCyan, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text('صافي الأرباح الشهرية', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: Colors.white, fontFamily: 'Cairo')),
                ],
              ),
              const SizedBox(height: 6),
              Text('آخر 12 شهر', style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
              const SizedBox(height: 24),
              SizedBox(
                height: 260,
                child: _sortedMonths.isEmpty
                    ? const Center(child: Text('لا توجد بيانات كافية', style: TextStyle(
                        color: AppTheme.textSecondary, fontFamily: 'Cairo')))
                    : _LineChart(
                        months: _sortedMonths,
                        values: _sortedMonths.map((m) => _monthlyProfit[m] ?? 0).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<String> months;
  final List<double> values;

  const _LineChart({required this.months, required this.values});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _LineChartPainter(months, values),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<String> months;
  final List<double> values;

  _LineChartPainter(this.months, this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paintW = size.width;
    final paintH = size.height;
    final maxVal = values.fold(0.0, (a, b) => a > b ? a : b);
    final minVal = values.fold(double.infinity, (a, b) => a < b ? a : b);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);
    final paddingLeft = 8.0;
    final paddingRight = 8.0;
    final paddingTop = 8.0;
    final paddingBottom = 24.0;
    final chartW = paintW - paddingLeft - paddingRight;
    final chartH = paintH - paddingTop - paddingBottom;

    if (chartW <= 0 || chartH <= 0) return;

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = paddingLeft + (i / (values.length - 1).clamp(1, values.length)) * chartW;
      final y = paddingTop + chartH - ((values[i] - minVal) / range) * chartH;
      points.add(Offset(x, y));
    }

    // gradient fill below line
    for (int i = 0; i < points.length - 1; i++) {
      final path = Path()
        ..moveTo(points[i].dx, points[i].dy)
        ..lineTo(points[i + 1].dx, points[i + 1].dy)
        ..lineTo(points[i + 1].dx, paintH - paddingBottom)
        ..lineTo(points[i].dx, paintH - paddingBottom)
        ..close();
      final frac = i / (points.length - 1).clamp(1, points.length);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.neonCyan.withValues(alpha: 0.25 - frac * 0.15),
              AppTheme.neonCyan.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(0, 0, paintW, paintH)),
      );
    }

    // draw line
    final linePaint = Paint()
      ..color = AppTheme.neonCyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }

    // draw dots
    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = AppTheme.neonCyan);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);
    }

    // x-axis labels
    for (int i = 0; i < months.length; i++) {
      final parts = months[i].split('-');
      final label = parts.length == 2 ? parts[1] : '';
      final x = paddingLeft + (i / (months.length - 1).clamp(1, months.length)) * chartW;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.6),
            fontSize: 10,
            fontFamily: 'Cairo',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, paintH - paddingBottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.months != months || old.values != values;
}
