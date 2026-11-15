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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final dialogContent = Container(
      width: screenWidth < 500 ? screenWidth * 0.95 : 520,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xB305192D) : Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, isDark),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  const SizedBox(height: 16),
                  _buildSummaryCard(isDark),
                  const SizedBox(height: 16),
                  _buildPriceSection(isDark),
                  const SizedBox(height: 16),
                  _buildWarehouseSection(isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: isDark
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: dialogContent,
              ),
            )
          : dialogContent,
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _avatarColor(fruitType.name).withValues(alpha: isDark ? 0.1 : 0.15),
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.warning.withValues(alpha: 0.15) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? AppTheme.warning.withValues(alpha: 0.3) : const Color(0xFFF59E0B),
                        ),
                      ),
                      child: Text(
                        fruitType.currency,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.warning : Colors.black,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  fruitType.code,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.primary.withValues(alpha: 0.8) : Colors.black,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? null : Colors.white,
        gradient: isDark
            ? LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.12),
                  AppTheme.accent.withValues(alpha: 0.08),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.primary.withValues(alpha: 0.2) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          _buildSummaryItem(
            Icons.inventory_2_outlined,
            'الكمية الإجمالية',
            '${_formatQty(_totalQuantity)} $_unitLabel',
            AppTheme.primary,
            isDark,
          ),
          Container(
            width: 1,
            height: 40,
            color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
          ),
          _buildSummaryItem(
            Icons.warehouse_outlined,
            'عدد المخازن',
            '${distribution.where((d) => (d['quantity'] as double? ?? 0) > 0).length}',
            AppTheme.accent,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: isDark ? color : const Color(0xFF0284C7)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? color : Colors.black,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : Colors.black,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'أسعار الشراء',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
            fontFamily: 'Cairo',
          ),
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
                isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPriceCard(
                'متوسط السعر',
                _formatPrice(fruitType.averagePurchasePrice),
                Icons.trending_up,
                fruitType.averagePurchasePrice != null ? AppTheme.info : AppTheme.textMuted,
                isDark,
              ),
            ),
          ],
        ),
        if (fruitType.lastPurchaseDate != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'آخر شراء: ${AppUtils.formatDate(DateTime.parse(fruitType.lastPurchaseDate!))}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.7) : Colors.black,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? color.withValues(alpha: 0.2) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: isDark ? color : const Color(0xFF0284C7)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? color : Colors.black,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : Colors.black,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseSection(bool isDark) {
    final activeDistribution = distribution.where((d) => (d['quantity'] as double? ?? 0) > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warehouse_outlined, size: 16, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
            const SizedBox(width: 8),
            Text(
              'التوزيع على المخازن',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (activeDistribution.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
              ),
            ),
            child: Center(
              child: Text(
                'لا يوجد مخزون في أي مخزن',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.6) : Colors.black,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
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
                color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppTheme.glassBorder.withValues(alpha: 0.3) : const Color(0xFFCBD5E1),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.accent.withValues(alpha: 0.12) : const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.warehouse_outlined,
                          size: 16,
                          color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stationName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            Text(
                              stationCode,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? AppTheme.accent.withValues(alpha: 0.7) : Colors.black87,
                                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_formatQty(qty)} $_unitLabel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.warning : Colors.black,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.7) : Colors.black,
                              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
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
                      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark
                            ? AppTheme.primary.withValues(alpha: 0.6 + (percentage / 100 * 0.4))
                            : const Color(0xFF0284C7),
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
