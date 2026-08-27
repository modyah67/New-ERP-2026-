import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class UpcomingShipmentsTable extends StatelessWidget {
  final List<Map<String, dynamic>> shipments;

  const UpcomingShipmentsTable({super.key, required this.shipments});

  Color _statusColor(String? status) {
    switch (status) {
      case 'pending': return AppTheme.warning;
      case 'active': return AppTheme.primary;
      case 'completed': return AppTheme.success;
      default: return AppTheme.textMuted;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'pending': return 'قيد الانتظار';
      case 'active': return 'نشط';
      case 'completed': return 'مكتمل';
      default: return status ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flight_takeoff, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            const Text(
              'الشحنات القادمة',
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
          child: shipments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flight, color: AppTheme.textMuted, size: 32),
                      const SizedBox(height: 8),
                      Text('لا توجد شحنات قادمة',
                          style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo')),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: shipments.length,
                  itemBuilder: (_, i) {
                    final s = shipments[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withAlpha(10)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                s['shipment_no']?.toString() ?? '—',
                                style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                s['destination']?.toString() ?? '—',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                s['date']?.toString()?.substring(0, 10) ?? '—',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo'),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _statusColor(s['status'] as String?).withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _statusLabel(s['status'] as String?),
                                style: TextStyle(
                                  color: _statusColor(s['status'] as String?),
                                  fontSize: 10,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class TopProductsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> products;

  const TopProductsWidget({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star, color: AppTheme.warning, size: 16),
            const SizedBox(width: 6),
            const Text(
              'أفضل المنتجات',
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
          child: products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2, color: AppTheme.textMuted, size: 32),
                      const SizedBox(height: 8),
                      Text('لا توجد منتجات',
                          style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo')),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: products.take(8).length,
                  itemBuilder: (_, i) {
                    final p = products[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p['name']?.toString() ?? '—',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${(p['quantity'] as num?)?.toInt() ?? 0}',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo'),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(p['value'] as num?)?.toStringAsFixed(0) ?? '0'} \$',
                              style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class QuickAnalyticsCards extends StatelessWidget {
  final Map<String, dynamic> analytics;

  const QuickAnalyticsCards({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final items = [
      {'label': 'متوسط الفاتورة', 'value': _formatCurrency((analytics['avgInvoice'] as num?)?.toDouble() ?? 0.0), 'icon': Icons.receipt, 'color': AppTheme.primary},
      {'label': 'هامش الربح', 'value': '${((analytics['profitMargin'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)}%', 'icon': Icons.trending_up, 'color': AppTheme.success},
      {'label': 'نسبة التحصيل', 'value': '${((analytics['collectionRate'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}%', 'icon': Icons.payments, 'color': AppTheme.accent},
      {'label': 'معدل الدوران', 'value': '${((analytics['inventoryTurnover'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)}x', 'icon': Icons.repeat, 'color': AppTheme.warning},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.analytics, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            const Text(
              'تحليلات سريعة',
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
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.4,
            children: items.map((item) => _miniCard(
              item['label'] as String,
              item['value'] as String,
              item['icon'] as IconData,
              item['color'] as Color,
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _miniCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          Text(label,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M ج.م';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K ج.م';
    return '${value.toStringAsFixed(0)} ج.م';
  }
}
