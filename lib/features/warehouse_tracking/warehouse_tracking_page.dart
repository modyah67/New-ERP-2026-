import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/models/station_model.dart';
import 'warehouse_tracking_cubit.dart';
import 'warehouse_tracking_state.dart';

class WarehouseTrackingPage extends StatefulWidget {
  const WarehouseTrackingPage({super.key});

  @override
  State<WarehouseTrackingPage> createState() => _WarehouseTrackingPageState();
}

class _WarehouseTrackingPageState extends State<WarehouseTrackingPage> {
  late final WarehouseTrackingCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = WarehouseTrackingCubit()..init();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isMobile, isDark),
              const SizedBox(height: 20),
              Expanded(child: _buildContent(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile, bool isDark) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.accent.withValues(alpha: 0.1)
                : const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.warehouse_outlined,
              color: isDark ? AppTheme.accent : const Color(0xFF0284C7), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('متابعة المخازن',
                    style: TextStyle(
                        fontSize: isMobile ? 22 : 28,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                BlocBuilder<WarehouseTrackingCubit, WarehouseTrackingState>(
                  buildWhen: (prev, curr) => curr is WarehouseTrackingLoaded,
                  builder: (context, state) {
                    final count = state is WarehouseTrackingLoaded
                        ? state.stations.length
                        : 0;
                    return Text('$count مخزن',
                        style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 13));
                  },
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.refresh_outlined,
              color: isDark ? Colors.white : Colors.black),
          tooltip: 'تحديث',
          onPressed: () => _cubit.loadStations(),
        ),
      ],
    );
  }

  Widget _buildContent(bool isDark) {
    return BlocBuilder<WarehouseTrackingCubit, WarehouseTrackingState>(
      builder: (context, state) {
        if (state is WarehouseTrackingLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is WarehouseTrackingError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 64,
                    color: AppTheme.danger.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(state.message,
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  onPressed: () => _cubit.loadStations(),
                ),
              ],
            ),
          );
        }
        if (state is WarehouseTrackingLoaded) {
          if (state.stations.isEmpty) {
            return _buildEmptyState(isDark);
          }
          return _buildGridView(state, isDark);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildGridView(WarehouseTrackingLoaded state, bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: state.stations.length,
      separatorBuilder: (_, __) => SizedBox(height: isMobile ? 10 : 16),
      itemBuilder: (context, index) {
        return _buildStationCard(
            state.stations[index],
            state.stationStats,
            state.stationProducts,
            state.stationValues,
            index,
            isDark);
      },
    );
  }

  Widget _buildStationCard(
      StationModel station,
      Map<String, Map<String, int>> stats,
      Map<String, List<Map<String, dynamic>>> allProducts,
      Map<String, Map<String, double>> stationValues,
      int index,
      bool isDark) {
    final stationStats = stats[station.id] ?? {};
    final purchaseCount = stationStats['purchases'] ?? 0;
    final lotCount = stationStats['lots'] ?? 0;
    final packingCount = stationStats['packing'] ?? 0;
    final transferCount = stationStats['transfers'] ?? 0;
    final materialTransferCount = stationStats['materialTransfers'] ?? 0;
    final totalMovements =
        purchaseCount + lotCount + packingCount + transferCount + materialTransferCount;
    final products = allProducts[station.id] ?? [];
    final totalFruitQty = products.fold<double>(0, (s, p) => s + (p['quantity'] as double? ?? 0));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 30)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3805192D) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? AppTheme.accent.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _openStationDetail(station),
                splashColor: AppTheme.accent.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.accent.withValues(alpha: 0.12)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: isDark
                                      ? AppTheme.accent.withValues(alpha: 0.25)
                                      : const Color(0xFFCBD5E1)),
                            ),
                            child: Icon(Icons.warehouse_outlined,
                                color: isDark ? AppTheme.accent : Colors.black87, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station.name,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? AppTheme.accent.withValues(alpha: 0.08)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: isDark
                                                ? Colors.transparent
                                                : const Color(0xFFCBD5E1)),
                                      ),
                                      child: Text(
                                        station.code,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? AppTheme.accent : Colors.black,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: station.isActive
                                            ? (isDark
                                                ? AppTheme.success.withValues(alpha: 0.1)
                                                : const Color(0xFFDCFCE7))
                                            : (isDark
                                                ? AppTheme.danger.withValues(alpha: 0.1)
                                                : const Color(0xFFFEE2E2)),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.transparent
                                              : (station.isActive
                                                  ? const Color(0xFF86EFAC)
                                                  : const Color(0xFFFCA5A5)),
                                        ),
                                      ),
                                      child: Text(
                                        station.isActive ? 'نشط' : 'غير نشط',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? (station.isActive ? AppTheme.success : AppTheme.danger)
                                              : (station.isActive
                                                  ? const Color(0xFF15803D)
                                                  : const Color(0xFFB91C1C)),
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? null : const Color(0xFFF1F5F9),
                              gradient: isDark
                                  ? const LinearGradient(colors: [AppTheme.primary, AppTheme.accent])
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              '$totalMovements حركة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildStatChip(Icons.shopping_cart_outlined, 'مشتريات', purchaseCount, AppTheme.primary, isDark),
                          _buildStatChip(Icons.eco_outlined, 'محاصيل', lotCount, AppTheme.accent, isDark),
                          _buildStatChip(Icons.checklist_outlined, 'تعبئة', packingCount, AppTheme.warning, isDark),
                          _buildStatChip(Icons.swap_horiz, 'تحويلات', transferCount, AppTheme.info, isDark),
                          _buildStatChip(Icons.inventory_2_outlined, 'مواد تعبئة', materialTransferCount, AppTheme.success, isDark),
                        ],
                      ),
                      if (products.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.primary.withValues(alpha: 0.06)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: isDark
                                    ? AppTheme.primary.withValues(alpha: 0.15)
                                    : const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.eco,
                                  size: 16,
                                  color: isDark
                                      ? AppTheme.primary.withValues(alpha: 0.8)
                                      : Colors.black87),
                              const SizedBox(width: 8),
                              Text(
                                '${products.length} صنف',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.primary : Colors.black,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${totalFruitQty.toStringAsFixed(0)} قطعة',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.warning : Colors.black,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildStatChip(IconData icon, String label, int count, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? color.withValues(alpha: 0.2) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isDark ? color : Colors.black87),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppTheme.textSecondary.withValues(alpha: 0.8)
                      : Colors.black)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? color.withValues(alpha: 0.2) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? color : Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warehouse_outlined,
              size: 72,
              color: isDark
                  ? AppTheme.textSecondary.withValues(alpha: 0.3)
                  : Colors.black38),
          const SizedBox(height: 16),
          Text(
            'لا توجد مخازن بعد',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            'أضف مخازن من صفحة المخازن الفرعية',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black87,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _openStationDetail(StationModel station) async {
    await context.push(
      '/warehouse-tracking/detail',
      extra: {'station': station, 'cubit': _cubit},
    );
    if (!mounted) return;
    _cubit.loadStations();
  }
}
