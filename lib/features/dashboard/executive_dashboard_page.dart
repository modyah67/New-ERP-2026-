import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/services/executive_dashboard_service.dart';
import '../../data/services/business_health_service.dart';

class ExecutiveDashboardPage extends StatefulWidget {
  const ExecutiveDashboardPage({super.key});

  @override
  State<ExecutiveDashboardPage> createState() => _ExecutiveDashboardPageState();
}

class _ExecutiveDashboardPageState extends State<ExecutiveDashboardPage> {
  final _dashService = ExecutiveDashboardService();
  final _healthService = BusinessHealthService();
  bool _loading = true;

  Map<String, dynamic> _kpis = {};
  Map<String, List<MapEntry<String, double>>> _trends = {};
  List<MapEntry<String, double>> _inventoryDist = [];
  List<Map<String, dynamic>> _topCustomers = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topShipments = [];
  List<Map<String, dynamic>> _topDestinations = [];
  Map<String, dynamic> _health = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _dashService.getKpis(),
        _dashService.getTrends(),
        _dashService.getInventoryDistribution(),
        _dashService.getTopCustomers(),
        _dashService.getTopProducts(),
        _dashService.getTopProfitableShipments(),
        _dashService.getTopDestinations(),
        _healthService.getHealthMetrics(),
      ]);
      if (!mounted) return;
      setState(() {
        _kpis = results[0] as Map<String, dynamic>;
        _trends = results[1] as Map<String, List<MapEntry<String, double>>>;
        _inventoryDist = results[2] as List<MapEntry<String, double>>;
        _topCustomers = results[3] as List<Map<String, dynamic>>;
        _topProducts = results[4] as List<Map<String, dynamic>>;
        _topShipments = results[5] as List<Map<String, dynamic>>;
        _topDestinations = results[6] as List<Map<String, dynamic>>;
        _health = results[7] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _f(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}م';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)}أ';
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      _buildKpiSection(),
                      const SizedBox(height: 20),
                      _buildHealthPanel(),
                      const SizedBox(height: 20),
                      _buildChartSection(),
                      const SizedBox(height: 20),
                      _buildInventoryDistSection(),
                      const SizedBox(height: 20),
                      _buildTopLists(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 20, right: 20, bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 50))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.dashboard_rounded, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('لوحة القيادة التنفيذية', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('Executive Dashboard', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(height: 10),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 2),
              Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiSection() {
    final kpis = _kpis;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('إيرادات اليوم', '${_f(kpis['today_revenue'])} ج.م', Icons.today_outlined, const Color(0xFF00E5FF))),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('إيرادات الشهر', '${_f(kpis['month_revenue'])} ج.م', Icons.date_range_outlined, AppTheme.primary)),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('مجمل الربح', '${_f(kpis['gross_profit'])} ج.م', Icons.trending_up_outlined, AppTheme.emerald)),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('صافي الربح', '${_f(kpis['net_profit'])} ج.م', Icons.monetization_on_outlined, const Color(0xFF00E676))),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('الخزينة', '${_f(kpis['treasury_balance'])} ج.م', Icons.account_balance_outlined, const Color(0xFF7C4DFF))),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('المدينون', '${_f(kpis['receivables'])} ج.م', Icons.people_outline, const Color(0xFFFF6F00))),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('الدائنون', '${_f(kpis['payables'])} ج.م', Icons.people_outline, const Color(0xFFD32F2F))),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('شحنات نشطة', '${kpis['active_shipments']}', Icons.local_shipping_outlined, const Color(0xFF00ACC1))),
        SizedBox(width: (MediaQuery.of(context).size.width - 50) / 5, child: _kpiCard('شيكات مفتوحة', '${kpis['open_cheques']}', Icons.receipt_outlined, const Color(0xFFF50057))),
      ],
    );
  }

  Widget _healthPanel() {
    final h = _health;
    final gm = (h['gross_margin_pct'] as num?)?.toDouble() ?? 0;
    final nm = (h['net_margin_pct'] as num?)?.toDouble() ?? 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.health_and_safety_outlined, color: AppTheme.emerald, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('مؤشرات الصحة المالية', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _healthMetric('هامش مجمل الربح', '${gm.toStringAsFixed(1)}%', _marginColor(gm)),
                  const SizedBox(width: 12),
                  _healthMetric('هامش صافي الربح', '${nm.toStringAsFixed(1)}%', _marginColor(nm)),
                  const SizedBox(width: 12),
                  _healthMetric('دوران المخزون', (h['inventory_turnover'] as num?)?.toStringAsFixed(2) ?? '0', AppTheme.info),
                  const SizedBox(width: 12),
                  _healthMetric('متوسط ربح الشحنة', '${_f((h['avg_shipment_profit'] as num?)?.toDouble() ?? 0)} ج.م', AppTheme.warning),
                  const SizedBox(width: 12),
                  _healthMetric('متوسط تكلفة الكرتون', '${_f((h['avg_cost_per_carton'] as num?)?.toDouble() ?? 0)} ج.م', const Color(0xFFFF6F00)),
                  const SizedBox(width: 12),
                  _healthMetric('متوسط إيراد الكرتون', '${_f((h['avg_revenue_per_carton'] as num?)?.toDouble() ?? 0)} ج.م', AppTheme.emerald),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _marginColor(double v) {
    if (v >= 20) return AppTheme.emerald;
    if (v >= 10) return AppTheme.warning;
    return const Color(0xFFD32F2F);
  }

  Widget _healthMetric(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo'), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthPanel() {
    return _loading ? const SizedBox.shrink() : _healthPanel();
  }

  Widget _glassContainer(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 30)),
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  Widget _buildChartSection() {
    final revTrend = _trends['revenue_trend'] ?? [];
    final profitTrend = _trends['profit_trend'] ?? [];
    final shipTrend = _trends['shipment_trend'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('الاتجاهات', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _glassContainer(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الإيرادات الشهرية', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: revTrend.isEmpty
                        ? const Center(child: Text('لا توجد بيانات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')))
                        : _LineChart(entries: revTrend, color: AppTheme.primary),
                  ),
                ],
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: _glassContainer(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('صافي الأرباح الشهرية', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: profitTrend.isEmpty
                        ? const Center(child: Text('لا توجد بيانات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')))
                        : _LineChart(entries: profitTrend, color: AppTheme.emerald),
                  ),
                ],
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: _glassContainer(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('عدد الشحنات شهرياً', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: shipTrend.isEmpty
                        ? const Center(child: Text('لا توجد بيانات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')))
                        : _LineChart(entries: shipTrend, color: AppTheme.info),
                  ),
                ],
              ),
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildInventoryDistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('توزيع المخزون', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        _glassContainer(
          SizedBox(
            height: 220,
            child: _inventoryDist.isEmpty
                ? const Center(child: Text('لا توجد بيانات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')))
                : _BarChart(entries: _inventoryDist),
          ),
        ),
      ],
    );
  }

  Widget _buildTopLists() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('القوائم العلوية', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildTopList('أفضل العملاء', _topCustomers, 'customer_name', 'total_revenue', 'ج.م')),
            const SizedBox(width: 12),
            Expanded(child: _buildTopList('أفضل المنتجات', _topProducts, 'product_name', 'total_weight', 'كجم')),
            const SizedBox(width: 12),
            Expanded(child: _buildTopList('أكثر الشحنات ربحاً', _topShipments, 'shipment_no', 'net_profit_egp', 'ج.م')),
            const SizedBox(width: 12),
            Expanded(child: _buildTopList('أفضل الوجهات', _topDestinations, 'destination', 'total_revenue', 'ج.م')),
          ],
        ),
      ],
    );
  }

  Widget _buildTopList(String title, List<Map<String, dynamic>> items, String nameKey, String valueKey, String unit) {
    return _glassContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          const SizedBox(height: 10),
          ...items.take(5).map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('${item[nameKey]}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis),
                ),
                Text('${_f((item[valueKey] as num?)?.toDouble() ?? 0)} $unit', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo')),
              ],
            ),
          )),
          if (items.isEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('لا توجد بيانات', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}

// ── Line Chart ──

class _LineChart extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final Color color;
  const _LineChart({required this.entries, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          CustomPaint(size: Size(constraints.maxWidth, constraints.maxHeight), painter: _LinePainter(entries, color)),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final Color color;
  _LinePainter(this.entries, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final values = entries.map((e) => e.value).toList();
    final maxVal = values.fold(0.0, (a, b) => a > b ? a : b);
    final minVal = values.fold(double.infinity, (a, b) => a < b ? a : b);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);
    const pl = 8, pr = 8, pt = 8, pb = 20;
    final cw = size.width - pl - pr;
    final ch = size.height - pt - pb;
    if (cw <= 0 || ch <= 0) return;

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = pl + (i / (values.length - 1).clamp(1, values.length)) * cw;
      final y = pt + ch - ((values[i] - minVal) / range) * ch;
      points.add(Offset(x, y));
    }

    for (int i = 0; i < points.length - 1; i++) {
      final path = Path()
        ..moveTo(points[i].dx, points[i].dy)
        ..lineTo(points[i + 1].dx, points[i + 1].dy)
        ..lineTo(points[i + 1].dx, size.height - pb)
        ..lineTo(points[i].dx, size.height - pb)
        ..close();
      final frac = i / (points.length - 1).clamp(1, points.length);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.25 - frac * 0.15), color.withValues(alpha: 0.02)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }

    for (final p in points) {
      canvas.drawCircle(p, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.entries != entries;
}

// ── Bar Chart ──

class _BarChart extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  const _BarChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          CustomPaint(size: Size(constraints.maxWidth, constraints.maxHeight), painter: _BarPainter(entries)),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  _BarPainter(this.entries);

  static const colors = [
    Color(0xFF10B981), Color(0xFF00E5FF), Color(0xFF7C4DFF),
    Color(0xFFFF6F00), Color(0xFFD32F2F), Color(0xFF00ACC1),
    Color(0xFFF50057), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFDD835),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    const pl = 8, pr = 8, pt = 8, pb = 24;
    final cw = size.width - pl - pr;
    final ch = size.height - pt - pb;
    if (cw <= 0 || ch <= 0) return;

    final maxVal = entries.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);
    final safeMax = maxVal > 0 ? maxVal : 1.0;
    final barCount = entries.length;
    final barW = (cw / barCount) * 0.6;
    final gap = (cw / barCount) * 0.4;

    for (int i = 0; i < barCount; i++) {
      final x = pl + i * (barW + gap) + gap / 2;
      final h = (entries[i].value / safeMax) * ch;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, pt + ch - h, barW, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = colors[i % colors.length].withValues(alpha: 0.7),
      );

      final label = entries[i].key.length > 6 ? '${entries[i].key.substring(0, 5)}..' : entries[i].key;
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 9, fontFamily: 'Cairo')),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, size.height - pb + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.entries != entries;
}
