import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/fruit_type_model.dart';

class FruitTypeDetailDialog extends StatelessWidget {
  final FruitTypeModel fruitType;
  final List<Map<String, dynamic>> distribution;

  const FruitTypeDetailDialog({
    super.key,
    required this.fruitType,
    required this.distribution,
  });

  double get _totalQuantity =>
      distribution.fold<double>(0, (sum, d) => sum + (d['quantity'] as double? ?? 0));

  String get _unitLabel => (fruitType.purchaseMode ?? fruitType.latestPurchaseMode) == 'carton' ? 'كرتونة' : 'كجم';

  String _formatPrice(double? price) {
    if (price == null) return '—';
    return '${AppUtils.formatNumber(price)} ${fruitType.currency}';
  }

  String _formatQty(double qty) {
    if (qty == 0) return '0';
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    return qty.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: const Color(0xCC05192D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 500 ? screenWidth * 0.95 : 520,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            decoration: const BoxDecoration(
              color: Color(0xB305192D),
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(context),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      children: [
                        const SizedBox(height: 16),
                        _buildSummaryCard(),
                        const SizedBox(height: 16),
                        _buildPriceSection(),
                        const SizedBox(height: 16),
                        _buildWarehouseSection(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _avatarColor(fruitType.name).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                fruitType.name.isNotEmpty ? fruitType.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _avatarColor(fruitType.name),
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fruitType.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        fruitType.currency,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.warning,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  fruitType.code,
                  style: TextStyle(fontSize: 12, color: AppTheme.primary.withValues(alpha: 0.8), fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.12),
            AppTheme.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _buildSummaryItem(
            Icons.inventory_2_outlined,
            'الكمية الإجمالية',
            '${_formatQty(_totalQuantity)} $_unitLabel',
            AppTheme.primary,
          ),
          Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.1)),
          _buildSummaryItem(
            Icons.warehouse_outlined,
            'عدد المخازن',
            '${distribution.where((d) => (d['quantity'] as double? ?? 0) > 0).length}',
            AppTheme.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.8), fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'أسعار الشراء',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildPriceCard(
                'آخر سعر شراء',
                _formatPrice(fruitType.latestPurchasePrice),
                Icons.attach_money,
                fruitType.latestPurchasePrice != null ? AppTheme.success : AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPriceCard(
                'متوسط السعر',
                _formatPrice(fruitType.averagePurchasePrice),
                Icons.trending_up,
                fruitType.averagePurchasePrice != null ? AppTheme.info : AppTheme.textMuted,
              ),
            ),
          ],
        ),
        if (fruitType.lastPurchaseDate != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'آخر شراء: ${AppUtils.formatDate(DateTime.parse(fruitType.lastPurchaseDate!))}',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.7), fontFamily: 'Cairo'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.8), fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseSection() {
    final activeDistribution = distribution.where((d) => (d['quantity'] as double? ?? 0) > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warehouse_outlined, size: 16, color: AppTheme.accent),
            const SizedBox(width: 8),
            const Text(
              'التوزيع على المخازن',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (activeDistribution.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'لا يوجد مخزون في أي مخزن',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary.withValues(alpha: 0.6), fontFamily: 'Cairo'),
              ),
            ),
          )
        else
          ...activeDistribution.map((d) {
            final qty = d['quantity'] as double? ?? 0;
            final percentage = _totalQuantity > 0 ? (qty / _totalQuantity * 100) : 0;
            final stationName = d['station_name']?.toString() ?? '';
            final stationCode = d['station_code']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.warehouse_outlined, size: 16, color: AppTheme.accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stationName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
                            ),
                            Text(
                              stationCode,
                              style: TextStyle(fontSize: 10, color: AppTheme.accent.withValues(alpha: 0.7), fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_formatQty(qty)} $_unitLabel',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.warning, fontFamily: 'Cairo'),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.7), fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _totalQuantity > 0 ? qty / _totalQuantity : 0,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primary.withValues(alpha: 0.6 + (percentage / 100 * 0.4)),
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  static Color _avatarColor(String name) {
    final colors = [
      AppTheme.primary,
      AppTheme.accent,
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFFF97316),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}
