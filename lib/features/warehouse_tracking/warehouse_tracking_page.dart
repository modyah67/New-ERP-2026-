import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
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
    final isMobile = MediaQuery.of(context).size.width < 600;
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isMobile),
              const SizedBox(height: 20),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.warehouse_outlined,
              color: AppTheme.accent, size: 22),
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
                        color: Colors.white,
                        fontFamily: 'Cairo')),
                BlocBuilder<WarehouseTrackingCubit, WarehouseTrackingState>(
                  buildWhen: (prev, curr) => curr is WarehouseTrackingLoaded,
                  builder: (context, state) {
                    final count = state is WarehouseTrackingLoaded
                        ? state.stations.length
                        : 0;
                    return Text('$count مخزن',
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 13));
                  },
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: 'تحديث',
          onPressed: () => _cubit.loadStations(),
        ),
      ],
    );
  }

  Widget _buildContent() {
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
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                  onPressed: () => _cubit.loadStations(),
                ),
              ],
            ),
          );
        }
        if (state is WarehouseTrackingLoaded) {
          if (state.stations.isEmpty) {
            return _buildEmptyState();
          }
          return _buildGridView(state);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildGridView(WarehouseTrackingLoaded state) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: state.stations.length,
      separatorBuilder: (_, __) => SizedBox(height: isMobile ? 10 : 16),
      itemBuilder: (context, index) {
        return _buildStationCard(
            state.stations[index], state.stationStats, state.stationProducts, state.stationValues, index);
      },
    );
  }

  Widget _buildStationCard(
      StationModel station, Map<String, Map<String, int>> stats, Map<String, List<Map<String, dynamic>>> allProducts, Map<String, Map<String, double>> stationValues, int index) {
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
    final currencyValues = stationValues[station.id] ?? {};

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
              color: const Color(0x3805192D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.06),
                  blurRadius: 20,
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
                              color: AppTheme.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                            ),
                            child: const Icon(Icons.warehouse_outlined, color: AppTheme.accent, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station.name,
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(station.code, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: station.isActive ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.danger.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        station.isActive ? 'نشط' : 'غير نشط',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: station.isActive ? AppTheme.success : AppTheme.danger, fontFamily: 'Cairo'),
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
                              gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.accent]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$totalMovements حركة',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildStatChip(Icons.shopping_cart_outlined, 'مشتريات', purchaseCount, AppTheme.primary),
                          _buildStatChip(Icons.eco_outlined, 'محاصيل', lotCount, AppTheme.accent),
                          _buildStatChip(Icons.checklist_outlined, 'تعبئة', packingCount, AppTheme.warning),
                          _buildStatChip(Icons.swap_horiz, 'تحويلات', transferCount, AppTheme.info),
                          _buildStatChip(Icons.inventory_2_outlined, 'مواد تعبئة', materialTransferCount, AppTheme.success),
                        ],
                      ),
                      if (products.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.eco, size: 16, color: AppTheme.primary.withValues(alpha: 0.8)),
                              const SizedBox(width: 8),
                              Text(
                                '${products.length} صنف',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary, fontFamily: 'Cairo'),
                              ),
                              const Spacer(),

                              Text(
                                '${totalFruitQty.toStringAsFixed(0)} قطعة',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.warning, fontFamily: 'Cairo'),
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

  Widget _buildStatChip(IconData icon, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppTheme.textSecondary.withValues(alpha: 0.8))),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$count', style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warehouse_outlined,
              size: 72,
              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text(
            'لا توجد مخازن بعد',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          const Text(
            'أضف مخازن من صفحة المخازن الفرعية',
            style: TextStyle(
                color: AppTheme.textSecondary,
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
