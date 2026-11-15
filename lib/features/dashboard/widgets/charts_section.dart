import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class LineChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final Color lineColor;

  const LineChartWidget({
    super.key,
    required this.data,
    this.lineColor = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    if (data.isEmpty) {
      return _buildEmpty('لا توجد بيانات مبيعات', isDark);
    }
    final maxVal = data.fold<double>(
        0, (s, e) => ((e['sales'] ?? 0) as num).toDouble() > s ? ((e['sales'] ?? 0) as num).toDouble() : s);
    final minVal = data.fold<double>(
        maxVal, (s, e) => ((e['sales'] ?? 0) as num).toDouble() < s ? ((e['sales'] ?? 0) as num).toDouble() : s);
    final range = maxVal - minVal > 0 ? maxVal - minVal : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'المبيعات آخر 30 يوم',
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _LineChartPainter(
                data: data,
                lineColor: lineColor,
                maxVal: maxVal,
                minVal: minVal,
                range: range,
                isDark: isDark,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildEmpty(String msg, bool isDark) {
    return Center(
      child: Text(msg,
          style: TextStyle(
              color: isDark ? AppTheme.textMuted : Colors.black,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo')),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final Color lineColor;
  final double maxVal;
  final double minVal;
  final double range;
  final bool isDark;

  _LineChartPainter({
    required this.data,
    required this.lineColor,
    required this.maxVal,
    required this.minVal,
    required this.range,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withAlpha(50), lineColor.withAlpha(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final gridPaint = Paint()
      ..color = isDark ? Colors.white.withAlpha(10) : const Color(0x180F172A)
      ..strokeWidth = 0.5;

    // Grid lines
    for (int i = 0; i < 4; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    final fillPath = Path();
    final dx = data.length > 1 ? size.width / (data.length - 1) : size.width;

    for (int i = 0; i < data.length; i++) {
      final x = i * dx;
      final y = size.height - (((data[i]['sales'] ?? 0) as num).toDouble() / range) * (size.height - 20) - 10;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Dots
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    for (int i = 0; i < data.length; i += 5) {
      final x = i * dx;
      final y = size.height - (((data[i]['sales'] ?? 0) as num).toDouble() / range) * (size.height - 20) - 10;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) => old.data != data;
}

class DonutChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final List<Color> colors;

  DonutChartWidget({
    super.key,
    required this.data,
    this.colors = const [
      AppTheme.primary, AppTheme.accent, AppTheme.success,
      AppTheme.warning, AppTheme.danger, Color(0xFF8B5CF6),
      Color(0xFFEC4899), Color(0xFF14B8A6),
    ],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? AppTheme.textSecondary : Colors.black;

    if (data.isEmpty) {
      return Center(
        child: Text('لا توجد بيانات',
            style: TextStyle(
                color: isDark ? AppTheme.textMuted : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
      );
    }
    final total = data.fold<double>(0, (s, e) => s + ((e['value'] ?? 0) as num).toDouble());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'توزيع المصروفات',
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  final size = constraints.maxWidth < constraints.maxHeight
                      ? constraints.maxWidth
                      : constraints.maxHeight;
                  return CustomPaint(
                    size: Size(size, size),
                    painter: _DonutPainter(data: data, colors: colors, total: total),
                  );
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(data.take(5).length, (i) {
                    final e = data[i];
                    final pct = total > 0 ? (((e['value'] ?? 0) as num).toDouble() / total * 100) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: colors[i % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${e['name']}',
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: primaryTextColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final List<Color> colors;
  final double total;

  _DonutPainter({required this.data, required this.colors, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    double startAngle = -1.5708; // start from top

    for (int i = 0; i < data.length; i++) {
      final value = ((data[i]['value'] ?? 0) as num).toDouble();
      final sweep = total > 0 ? (value / total) * 6.2832 : 0.0;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }

    // Center hole
    final holePaint = Paint()
      ..color = const Color(0x1A0A1E3A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.55, holePaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.data != data;
}

class DestinationsMapWidget extends StatelessWidget {
  final List<Map<String, dynamic>> destinations;

  const DestinationsMapWidget({super.key, required this.destinations});

  static const _cyan = Color(0xFF3FD4E8);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top5 = destinations.take(5).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0b1a2e) : Colors.white,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: isDark ? null : Border.all(color: AppTheme.lightBorder, width: 1.5),
        ),
        child: Stack(
          children: [
            if (isDark) ...[
              // Triple glow border — outer (widest, lowest opacity)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cyan.withValues(alpha: 0.05), width: 10),
                  ),
                ),
              ),
              // Triple glow border — middle
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _cyan.withValues(alpha: 0.12), width: 5),
                  ),
                ),
              ),
              // Triple glow border — inner (thinnest, highest opacity)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _cyan.withValues(alpha: 0.90), width: 1.5),
                  ),
                ),
              ),
            ],
            // Content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'الدول المصدر لها',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      // Compass/globe badge — overlapping top edge
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0d2138) : const Color(0xFFE0F2FE),
                          shape: BoxShape.circle,
                          border: Border.all(color: _cyan, width: 1.5),
                        ),
                        child: const Icon(Icons.explore, color: _cyan, size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Map + List
                  Expanded(
                    child: destinations.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.public, color: isDark ? AppTheme.textMuted : Colors.black87, size: 36),
                                const SizedBox(height: 8),
                                Text('لا توجد وجهات تصدير بعد',
                                    style: TextStyle(
                                      color: isDark ? AppTheme.textMuted : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    )),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              // Map section (fixed height)
                              const SizedBox(
                                height: 100,
                                child: _FlatWorldMap(),
                              ),
                              const SizedBox(height: 8),
                              // Country list
                              Expanded(
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: top5.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, i) {
                                    final d = top5[i];
                                    return _CountryRow(
                                      rank: i + 1,
                                      name: d['name']?.toString() ?? '—',
                                      totalValue: (d['total_value'] as num?)?.toDouble() ?? 0.0,
                                      totalWeight: (d['total_weight'] as num?)?.toDouble() ?? 0.0,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  final int rank;
  final String name;
  final double totalValue;
  final double totalWeight;

  const _CountryRow({
    required this.rank,
    required this.name,
    required this.totalValue,
    required this.totalWeight,
  });

  static const _cyan = Color(0xFF3FD4E8);

  String _fmtValue(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtWeight(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}t';
    return '${v.toStringAsFixed(0)}kg';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemBg = isDark ? const Color(0xFF0a1a30) : const Color(0xFFF8FAFC);
    final itemBorder = isDark ? const Color(0xFF1c3a52) : const Color(0xFFCBD5E1);
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? const Color(0xFF8fa5bd) : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: itemBorder, width: 1),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: _cyan,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Country name
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Value + weight
          if (totalValue > 0 || totalWeight > 0)
            Text(
              '${_fmtValue(totalValue)} EGP · ${_fmtWeight(totalWeight)}',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          const SizedBox(width: 6),
          // Map-pin icon
          const Icon(Icons.location_on_outlined, color: _cyan, size: 14),
        ],
      ),
    );
  }
}

class _FlatWorldMap extends StatelessWidget {
  const _FlatWorldMap();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: _WorldMapPainter(isDark: isDark),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  final bool isDark;
  _WorldMapPainter({this.isDark = true});

  @override
  void paint(Canvas canvas, Size size) {
    // Background (ocean)
    final oceanPaint = Paint()
      ..color = isDark ? const Color(0xFF0d2138) : const Color(0xFFF1F5F9)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), oceanPaint);

    // Graticule grid (~20° step)
    final gratPaint = Paint()
      ..color = isDark ? const Color(0xFF1e3a54).withValues(alpha: 0.4) : const Color(0xFFCBD5E1).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;

    final minLon = -170.0, maxLon = 180.0;
    final minLat = -56.0, maxLat = 82.0;
    final w = size.width;
    final h = size.height;
    double px(double lon) => (lon - minLon) / (maxLon - minLon) * w;
    double py(double lat) => (maxLat - lat) / (maxLat - minLat) * h;

    // Vertical grid lines (every 20° longitude)
    for (double lon = -160; lon <= 180; lon += 20) {
      final x = px(lon);
      canvas.drawLine(Offset(x, 0), Offset(x, h), gratPaint);
    }
    // Horizontal grid lines (every 20° latitude)
    for (double lat = -40; lat <= 80; lat += 20) {
      final y = py(lat);
      canvas.drawLine(Offset(0, y), Offset(w, y), gratPaint);
    }

    // Continent fill
    final mapPaint = Paint()
      ..color = isDark ? const Color(0xFF15304a) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF0d2138) : const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    // Africa
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(-17), py(15)), Offset(px(10), py(5)), Offset(px(12), py(-34)),
      Offset(px(32), py(-34)), Offset(px(42), py(-11)), Offset(px(51), py(12)),
      Offset(px(44), py(30)), Offset(px(37), py(37)), Offset(px(10), py(37)),
      Offset(px(-17), py(35)), Offset(px(-17), py(15)),
    ]);

    // Europe
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(-10), py(36)), Offset(px(3), py(36)), Offset(px(3), py(43)),
      Offset(px(-10), py(43)),
    ]);
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(-10), py(43)), Offset(px(0), py(48)), Offset(px(5), py(51)),
      Offset(px(15), py(54)), Offset(px(24), py(55)), Offset(px(30), py(60)),
      Offset(px(40), py(62)), Offset(px(32), py(48)), Offset(px(28), py(41)),
      Offset(px(20), py(40)), Offset(px(12), py(44)), Offset(px(5), py(44)),
      Offset(px(-10), py(43)),
    ]);

    // Asia (mainland)
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(26), py(12)), Offset(px(35), py(12)), Offset(px(40), py(15)),
      Offset(px(48), py(12)), Offset(px(55), py(25)), Offset(px(62), py(25)),
      Offset(px(68), py(23)), Offset(px(75), py(8)), Offset(px(78), py(15)),
      Offset(px(80), py(22)), Offset(px(88), py(22)), Offset(px(92), py(18)),
      Offset(px(98), py(16)), Offset(px(105), py(10)), Offset(px(105), py(22)),
      Offset(px(110), py(18)), Offset(px(118), py(24)), Offset(px(120), py(33)),
      Offset(px(127), py(35)), Offset(px(130), py(42)), Offset(px(135), py(35)),
      Offset(px(140), py(38)), Offset(px(140), py(46)), Offset(px(132), py(48)),
      Offset(px(128), py(50)), Offset(px(120), py(54)), Offset(px(110), py(60)),
      Offset(px(100), py(68)), Offset(px(80), py(72)), Offset(px(68), py(66)),
      Offset(px(60), py(56)), Offset(px(50), py(45)), Offset(px(40), py(42)),
      Offset(px(30), py(42)), Offset(px(26), py(42)), Offset(px(26), py(12)),
    ]);

    // North America
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(-168), py(72)), Offset(px(-140), py(72)), Offset(px(-125), py(68)),
      Offset(px(-120), py(60)), Offset(px(-110), py(58)), Offset(px(-95), py(58)),
      Offset(px(-82), py(52)), Offset(px(-68), py(48)), Offset(px(-65), py(44)),
      Offset(px(-70), py(30)), Offset(px(-82), py(25)), Offset(px(-85), py(15)),
      Offset(px(-90), py(15)), Offset(px(-100), py(18)), Offset(px(-105), py(20)),
      Offset(px(-118), py(32)), Offset(px(-122), py(38)), Offset(px(-125), py(48)),
      Offset(px(-140), py(60)), Offset(px(-155), py(60)), Offset(px(-168), py(65)),
      Offset(px(-168), py(72)),
    ]);

    // Central America + Caribbean
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(-85), py(15)), Offset(px(-82), py(10)), Offset(px(-78), py(8)),
      Offset(px(-82), py(15)), Offset(px(-85), py(15)),
    ]);

    // South America
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(-80), py(10)), Offset(px(-60), py(5)), Offset(px(-50), py(2)),
      Offset(px(-35), py(-5)), Offset(px(-35), py(-18)), Offset(px(-40), py(-22)),
      Offset(px(-48), py(-28)), Offset(px(-53), py(-34)), Offset(px(-65), py(-55)),
      Offset(px(-68), py(-53)), Offset(px(-73), py(-45)), Offset(px(-75), py(-30)),
      Offset(px(-75), py(-18)), Offset(px(-78), py(-5)), Offset(px(-80), py(5)),
      Offset(px(-80), py(10)),
    ]);

    // Australia
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(114), py(-11)), Offset(px(130), py(-12)), Offset(px(138), py(-12)),
      Offset(px(148), py(-15)), Offset(px(153), py(-25)), Offset(px(150), py(-33)),
      Offset(px(140), py(-38)), Offset(px(130), py(-32)), Offset(px(116), py(-35)),
      Offset(px(114), py(-22)), Offset(px(114), py(-11)),
    ]);

    // Greenland
    _drawContinent(canvas, mapPaint, borderPaint, [
      Offset(px(-55), py(60)), Offset(px(-22), py(60)), Offset(px(-18), py(65)),
      Offset(px(-20), py(76)), Offset(px(-35), py(82)), Offset(px(-55), py(82)),
      Offset(px(-60), py(75)), Offset(px(-55), py(60)),
    ]);
  }

  void _drawContinent(Canvas canvas, Paint fill, Paint stroke, List<Offset> pts) {
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _WorldMapPainter old) => false;
}
