import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class KpiCard extends StatefulWidget {
  final String title;
  final double value;
  final double change;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.change = 0,
    required this.icon,
    required this.color,
    this.onTap,
    this.loading = false,
  });

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (widget.loading) return _buildSkeleton(isDark);

    final isPositive = widget.change >= 0;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final mutedTextColor = isDark ? AppTheme.textMuted : Colors.black;
    final cardBg = isDark ? const Color(0x1A0A1E3A) : Colors.white;
    final cardBorder = isDark
        ? (_hovered ? widget.color.withAlpha(80) : AppTheme.glassBorder.withAlpha(60))
        : (_hovered ? widget.color.withAlpha(140) : AppTheme.lightBorder);
    final cardShadows = isDark
        ? (_hovered
            ? [
                BoxShadow(
                  color: widget.color.withAlpha(20),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : <BoxShadow>[])
        : [
            BoxShadow(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.15)
                  : const Color(0x0A0F172A),
              blurRadius: _hovered ? 16 : 8,
              offset: Offset(0, _hovered ? 6 : 2),
            ),
          ];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        transform: _hovered
            ? Matrix4.translationValues(0.0, -4.0, 0.0)
            : Matrix4.identity(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder),
                    boxShadow: cardShadows,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: widget.color.withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(widget.icon, color: widget.color, size: 18),
                          ),
                          const Spacer(),
                          _buildChangeBadge(isPositive, isDark),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatValue(widget.value),
                        style: TextStyle(
                          color: primaryTextColor,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: mutedTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildMiniSparkline(isPositive),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChangeBadge(bool isPositive, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isPositive ? AppTheme.success : AppTheme.danger).withAlpha(isDark ? 20 : 30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${isPositive ? '+' : ''}${widget.change.toStringAsFixed(1)}%',
        style: TextStyle(
          color: isDark
              ? (isPositive ? AppTheme.success : AppTheme.danger)
              : (isPositive ? const Color(0xFF047857) : const Color(0xFFB91C1C)),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }

  Widget _buildMiniSparkline(bool isPositive) {
    return SizedBox(
      height: 18,
      child: CustomPaint(
        size: const Size(double.infinity, 24),
        painter: _SparklinePainter(
          color: widget.color,
          data: [0.2, 0.5, 0.3, 0.7, 0.4, 0.9, 0.6, 0.8, 0.5, 0.95],
        ),
      ),
    );
  }

  Widget _buildSkeleton(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x1A0A1E3A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppTheme.glassBorder.withAlpha(60) : AppTheme.lightBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 40, height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: 80, height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 60, height: 14,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatValue(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

class _SparklinePainter extends CustomPainter {
  final Color color;
  final List<double> data;

  _SparklinePainter({required this.color, required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color.withAlpha(60)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withAlpha(40), color.withAlpha(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();
    final dx = size.width / (data.length - 1);
    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal > 0 ? maxVal - minVal : 1.0;

    for (int i = 0; i < data.length; i++) {
      final x = i * dx;
      final y = size.height - ((data[i] - minVal) / range) * (size.height - 4) - 2;
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
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
