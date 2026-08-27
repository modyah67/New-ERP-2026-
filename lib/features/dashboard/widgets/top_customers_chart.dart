import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class TopCustomersBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> customers;

  const TopCustomersBarChart({super.key, required this.customers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            const Text(
              'أفضل العملاء',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: customers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, color: AppTheme.textMuted, size: 32),
                      const SizedBox(height: 8),
                      Text('لا يوجد عملاء بعد',
                          style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo')),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: customers.take(6).length,
                  itemBuilder: (_, i) {
                    final c = customers[i];
                    final total = (c['total'] as num?)?.toDouble() ?? 0.0;
                    final maxVal = (customers.first['total'] as num?)?.toDouble() ?? 1.0;
                    final pct = maxVal > 0 ? total / maxVal : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                c['name']?.toString() ?? '—',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Spacer(),
                              Text(
                                _formatCurrency(total),
                                style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: Colors.white.withAlpha(8),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _barColor(i),
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _barColor(int index) {
    final colors = [AppTheme.primary, AppTheme.accent, AppTheme.success, AppTheme.warning, AppTheme.cyan, AppTheme.primary];
    return colors[index % colors.length];
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toStringAsFixed(0);
  }
}
