import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../data/models/fruit_type_group_model.dart';
import '../../../data/models/fruit_type_model.dart';

class UnifiedFruitCard extends StatelessWidget {
  final FruitTypeGroupModel group;
  final int index;
  final double Function(FruitTypeModel item) getTotalQuantity;
  final int Function(FruitTypeModel item) getWarehouseCount;
  final void Function(FruitTypeModel item) onTapItem;
  final void Function(FruitTypeModel item)? onEditItem;

  const UnifiedFruitCard({
    super.key,
    required this.group,
    required this.index,
    required this.getTotalQuantity,
    required this.getWarehouseCount,
    required this.onTapItem,
    this.onEditItem,
  });

  Color _avatarColor(String name) {
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

  String _formatQty(double? qty) {
    if (qty == null || qty == 0) return '0';
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    return qty.toStringAsFixed(1);
  }

  String _formatPrice(double? price, {String? currency}) {
    if (price == null || price == 0) return '—';
    final curr = currency ?? group.currency;
    return '${AppUtils.formatNumber(price)} $curr';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDual = group.isDualMode;
    final primary = group.primaryItem;
    final avatarColor = _avatarColor(group.baseName);

    // Calculate overall stock presence
    double overallQty = 0;
    for (final it in group.allItems) {
      overallQty += getTotalQuantity(it);
    }
    final hasStock = overallQty > 0;
    final overallStockColor = !hasStock
        ? AppTheme.danger
        : (overallQty < 1000 ? AppTheme.warning : AppTheme.success);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 20)),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: isDark ? null : Colors.white,
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF0C345C), Color(0xFF071E3A)],
                )
              : null,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? (isDual
                    ? AppTheme.accent.withValues(alpha: 0.4)
                    : overallStockColor.withValues(alpha: 0.3))
                : (isDual ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
            width: isDual ? 1.8 : 1.2,
          ),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: isDual
                        ? AppTheme.accent.withValues(alpha: 0.1)
                        : overallStockColor.withValues(alpha: 0.08),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Accent Indicator Line
            Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                gradient: LinearGradient(
                  colors: isDual
                      ? [AppTheme.accent, const Color(0xFF10B981)]
                      : [overallStockColor, overallStockColor.withValues(alpha: 0.2)],
                ),
              ),
            ),

            // Master Card Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: _buildMasterHeader(context, avatarColor, isDual, primary, isDark),
            ),

            // Content Area: Dual Mode vs Single Mode
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: isDual
                    ? _buildDualModeSections(context, isDark)
                    : _buildSingleModeSection(context, primary, isDark),
              ),
            ),

            // Bottom Valuation Footer
            _buildValuationFooter(isDark),
          ],
        ),
      ),
    );
  }

  // ── Master Header ──
  Widget _buildMasterHeader(
    BuildContext context,
    Color avatarColor,
    bool isDual,
    FruitTypeModel primary,
    bool isDark,
  ) {
    final letter = group.baseName.isNotEmpty ? group.baseName[0].toUpperCase() : '?';

    return Row(
      children: [
        // Avatar
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                avatarColor.withValues(alpha: 0.25),
                avatarColor.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: avatarColor.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: avatarColor,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Base Name & Badges
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.baseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isDual)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? null : const Color(0xFFE0F2FE),
                        gradient: isDark
                            ? LinearGradient(
                                colors: [
                                  AppTheme.accent.withValues(alpha: 0.25),
                                  const Color(0xFF10B981).withValues(alpha: 0.2),
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? AppTheme.accent.withValues(alpha: 0.4) : const Color(0xFF0284C7),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alt_route, size: 10, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                          const SizedBox(width: 3),
                          Text(
                            'صنف مشترك',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.accent : Colors.black,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? (group.hasCarton ? AppTheme.accent : const Color(0xFF10B981)).withValues(alpha: 0.15)
                            : (group.hasCarton ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? (group.hasCarton ? AppTheme.accent : const Color(0xFF10B981)).withValues(alpha: 0.3)
                              : (group.hasCarton ? const Color(0xFFBAE6FD) : const Color(0xFF86EFAC)),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            group.hasCarton ? Icons.inventory_2_outlined : Icons.scale_outlined,
                            size: 10,
                            color: isDark
                                ? (group.hasCarton ? AppTheme.accent : const Color(0xFF10B981))
                                : (group.hasCarton ? const Color(0xFF0284C7) : const Color(0xFF16A34A)),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            group.hasCarton ? 'بالكرتونة' : 'بالوزن',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? (group.hasCarton ? AppTheme.accent : const Color(0xFF10B981))
                                  : Colors.black,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 6),
                  // Currency Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.warning.withValues(alpha: 0.12) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: isDark ? AppTheme.warning.withValues(alpha: 0.3) : const Color(0xFFF59E0B)),
                    ),
                    child: Text(
                      group.currency,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.warning : Colors.black,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Dual Mode Sub-Sections ──
  Widget _buildDualModeSections(BuildContext context, bool isDark) {
    final weight = group.weightItem!;
    final carton = group.cartonItem!;

    final wQty = getTotalQuantity(weight);
    final cQty = getTotalQuantity(carton);

    final wHasStock = wQty > 0;
    final cHasStock = cQty > 0;

    final wColor = !wHasStock
        ? AppTheme.danger
        : (wQty < 1000 ? AppTheme.warning : const Color(0xFF10B981));
    final cColor = !cHasStock
        ? AppTheme.danger
        : (cQty < 200 ? AppTheme.warning : AppTheme.accent);

    final wPrice = weight.averagePurchasePrice ?? weight.latestPurchasePrice;
    final cPrice = carton.latestPricePerCarton ?? carton.averagePurchasePrice ?? carton.latestPurchasePrice;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 1. Weight Sub-Tile
        _buildSubTile(
          context: context,
          item: weight,
          title: 'شراء بالوزن',
          icon: Icons.scale_outlined,
          themeColor: const Color(0xFF10B981),
          code: weight.code,
          qtyText: '${_formatQty(wQty)} كجم',
          stockStatusColor: wColor,
          stockStatusLabel: !wHasStock ? 'نفذ' : (wQty < 1000 ? 'منخفض' : 'متوفر'),
          priceLabel: 'متوسط السعر',
          priceValue: _formatPrice(wPrice, currency: weight.currency),
          isDark: isDark,
          onTap: () => onTapItem(weight),
        ),

        const SizedBox(height: 6),

        // 2. Carton Sub-Tile
        _buildSubTile(
          context: context,
          item: carton,
          title: 'شراء بالكرتونة',
          icon: Icons.inventory_2_outlined,
          themeColor: AppTheme.accent,
          code: carton.code,
          qtyText: '${_formatQty(cQty)} كرتونة',
          stockStatusColor: cColor,
          stockStatusLabel: !cHasStock ? 'نفذ' : (cQty < 200 ? 'منخفض' : 'متوفر'),
          priceLabel: 'سعر الكرتونة',
          priceValue: _formatPrice(cPrice, currency: carton.currency),
          isDark: isDark,
          onTap: () => onTapItem(carton),
        ),
      ],
    );
  }

  // ── Helper Sub-Tile for Dual Mode ──
  Widget _buildSubTile({
    required BuildContext context,
    required FruitTypeModel item,
    required String title,
    required IconData icon,
    required Color themeColor,
    required String code,
    required String qtyText,
    required Color stockStatusColor,
    required String stockStatusLabel,
    required String priceLabel,
    required String priceValue,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: themeColor.withValues(alpha: 0.2),
        hoverColor: themeColor.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3505192D) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? themeColor.withValues(alpha: 0.25) : const Color(0xFFCBD5E1),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sub Header: Icon + Title + Code
              Row(
                children: [
                  Icon(icon, size: 14, color: isDark ? themeColor : const Color(0xFF0284C7)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? themeColor : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Code pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark ? themeColor.withValues(alpha: 0.15) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isDark ? themeColor.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? themeColor : Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 9, color: isDark ? AppTheme.textSecondary : Colors.black54),
                ],
              ),
              const SizedBox(height: 4),

              // Middle: Stock Quantity & Status Dot
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: stockStatusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            stockStatusLabel,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              color: isDark ? stockStatusColor : (stockStatusColor == AppTheme.danger ? AppTheme.danger : Colors.black),
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        qtyText,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 2),

              // Bottom: Pricing
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9,
                        color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        priceValue,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? themeColor : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Single Mode Section ──
  Widget _buildSingleModeSection(BuildContext context, FruitTypeModel item, bool isDark) {
    final qty = getTotalQuantity(item);
    final hasStock = qty > 0;
    final isCarton = (item.purchaseMode ?? item.latestPurchaseMode) == 'carton';
    final unitLabel = isCarton ? 'كرتونة' : 'كجم';
    final stockColor = !hasStock
        ? AppTheme.danger
        : (qty < 1000 ? AppTheme.warning : AppTheme.success);
    final stockLabel = !hasStock ? 'لا يوجد مخزون' : (qty < 1000 ? 'منخفض' : 'متوفر');

    final unitPrice = item.averagePurchasePrice ?? item.latestPurchasePrice ?? 0.0;
    final whCount = getWarehouseCount(item);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTapItem(item),
        borderRadius: BorderRadius.circular(14),
        splashColor: AppTheme.primary.withValues(alpha: 0.2),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3505192D) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? stockColor.withValues(alpha: 0.2) : const Color(0xFFCBD5E1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Code & Warehouse count
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.primary.withValues(alpha: 0.18) : const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFBAE6FD)),
                    ),
                    child: Text(
                      'كود: ${item.code}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.primary : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.warehouse_outlined, size: 13, color: isDark ? AppTheme.textSecondary : Colors.black),
                      const SizedBox(width: 4),
                      Text(
                        '$whCount مخازن',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? AppTheme.textSecondary : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Stock Status & Large Quantity
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: stockColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: stockColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          stockLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Cairo',
                            color: isDark ? stockColor : (stockColor == AppTheme.danger ? AppTheme.danger : Colors.black),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_formatQty(qty)} $unitLabel',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Cairo',
                      color: isDark ? stockColor : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // Unit price row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isCarton ? 'سعر الكرتونة' : 'متوسط السعر',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      color: isDark ? AppTheme.textSecondary : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatPrice(unitPrice > 0 ? unitPrice : null, currency: item.currency),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Cairo',
                      color: isDark ? AppTheme.accent : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Combined Stock Valuation Footer ──
  Widget _buildValuationFooter(bool isDark) {
    double totalVal = 0;
    for (final it in group.allItems) {
      final sv = it.totalStockValue;
      if (sv != null && sv > 0) {
        totalVal += sv;
      } else {
        final qty = getTotalQuantity(it);
        final pr = it.averagePurchasePrice ?? it.latestPurchasePrice ?? 0.0;
        totalVal += (qty * pr);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? null : const Color(0xFFF0FDF4),
          gradient: isDark
              ? LinearGradient(
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.12),
                    AppTheme.accent.withValues(alpha: 0.04),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppTheme.accent.withValues(alpha: 0.18) : const Color(0xFF86EFAC),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monetization_on_outlined, size: 14, color: isDark ? AppTheme.accent : const Color(0xFF16A34A)),
            const SizedBox(width: 5),
            Text(
              group.isDualMode ? 'إجمالي القيمة: ' : 'قيمة المخزون: ',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Cairo',
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatPrice(totalVal > 0 ? totalVal : null, currency: group.currency),
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: isDark ? AppTheme.accent : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
