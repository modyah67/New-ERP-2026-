import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/models/station_model.dart';
import 'station_cubit.dart';
import 'station_state.dart';
import 'station_form_dialog.dart';

class StationsPage extends StatefulWidget {
  const StationsPage({super.key});

  @override
  State<StationsPage> createState() => _StationsPageState();
}

class _StationsPageState extends State<StationsPage> {
  late final StationCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = StationCubit()..init();
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
              _buildSearchBar(),
              const SizedBox(height: 16),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.store_outlined, color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('المخازن', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: isMobile ? 22 : 28, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              BlocBuilder<StationCubit, StationState>(
                buildWhen: (prev, curr) => curr is StationLoaded,
                builder: (context, state) {
                  final count = state is StationLoaded ? state.stations.length : 0;
                  return Text('$count محطة', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13));
                },
              ),
            ]),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_outlined), tooltip: 'تحديث',
          onPressed: () => _cubit.loadAll(reset: true),
        ),
        const SizedBox(width: 4),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(isMobile ? 'إضافة' : 'إضافة محطة'),
          onPressed: () async {
            await _cubit.prepareAddForm();
            _showFormDialog();
          },
        ),
        ],
      );
  }

  Widget _buildSearchBar() {
    return TextField(
      onChanged: _cubit.onSearchChanged,
      decoration: InputDecoration(
        hintText: 'بحث بالكود أو الاسم...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: BlocBuilder<StationCubit, StationState>(
          buildWhen: (prev, curr) => curr is StationLoaded,
          builder: (context, state) {
            final query = state is StationLoaded ? state.searchQuery : '';
            if (query.isEmpty) return const SizedBox.shrink();
            return IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _cubit.onSearchChanged(''));
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    return BlocBuilder<StationCubit, StationState>(
      builder: (context, state) {
        if (state is StationLoading) return const Center(child: CircularProgressIndicator());
        if (state is StationError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.danger.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(state.message, style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                  onPressed: () => _cubit.loadAll(reset: true),
                ),
              ],
            ),
          );
        }
        if (state is StationLoaded) {
          if (state.stations.isEmpty) {
            return _buildEmptyState(state.searchQuery);
          }
          return _buildGridView(state);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildGridView(StationLoaded state) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final int crossAxisCount;
    final double childAspectRatio;

    if (screenWidth < 320) {
      crossAxisCount = 1;
      childAspectRatio = 1.45;
    } else if (isMobile) {
      crossAxisCount = 2;
      childAspectRatio = screenWidth < 380 ? 0.68 : 0.72;
    } else if (screenWidth > 1400) {
      crossAxisCount = 4;
      childAspectRatio = 0.85;
    } else if (screenWidth > 900) {
      crossAxisCount = 3;
      childAspectRatio = 0.85;
    } else {
      crossAxisCount = 2;
      childAspectRatio = 0.82;
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: isMobile ? 8 : 16,
        mainAxisSpacing: isMobile ? 8 : 16,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: state.stations.length,
      itemBuilder: (context, index) {
        return _buildStationCard(state.stations[index], index, isMobile: isMobile);
      },
    );
  }

  Widget _buildStationCard(StationModel station, int index, {bool isMobile = false}) {
    final avatarSize = isMobile ? 34.0 : 40.0;
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
        borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x3805192D),
              borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
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
                borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
                onTap: () => _showStationDetails(station),
                splashColor: AppTheme.accent.withValues(alpha: 0.05),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 8 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: avatarSize,
                            height: avatarSize,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                            ),
                            child: Icon(Icons.location_on_outlined, color: AppTheme.accent, size: isMobile ? 18 : 22),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: station.isActive ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              station.isActive ? 'نشط' : 'غير نشط',
                              style: TextStyle(fontSize: isMobile ? 8 : 9, fontWeight: FontWeight.bold, color: station.isActive ? AppTheme.success : AppTheme.danger, fontFamily: 'Cairo'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: station.isMain ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          station.isMain ? 'رئيسي' : 'فرعي',
                          style: TextStyle(fontSize: isMobile ? 8 : 9, fontWeight: FontWeight.bold, color: station.isMain ? AppTheme.primary : AppTheme.accent, fontFamily: 'Cairo'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        station.name,
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold, color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          station.code,
                          style: TextStyle(
                            fontFamily: 'Cairo', fontSize: isMobile ? 10 : 11, fontWeight: FontWeight.bold, color: AppTheme.accent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (station.description != null && station.description!.isNotEmpty) ...[
                        Text(
                          station.description!,
                          style: TextStyle(
                            fontFamily: 'Cairo', fontSize: isMobile ? 10 : 11,
                            color: AppTheme.textSecondary.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          _buildQuickAction(Icons.visibility_outlined, AppTheme.primary, 'عرض التفاصيل', () => _showStationDetails(station), isMobile: isMobile),
                        ],
                      ),
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

  Widget _buildQuickAction(IconData icon, Color color, String tooltip, VoidCallback onTap, {bool isMobile = false}) {
    final size = isMobile ? 26.0 : 32.0;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: isMobile ? 14 : 16, color: color),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String searchQuery) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_mall_directory_outlined, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty ? 'لا توجد محطات بعد' : 'لا توجد نتائج للبحث',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty ? 'اضغط "إضافة محطة" لإضافة أول محطة' : 'جرب كلمة بحث مختلفة',
            style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة محطة'),
              onPressed: () async {
                await _cubit.prepareAddForm();
                _showFormDialog();
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showFormDialog({StationModel? station}) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: _cubit,
        child: StationFormDialog(station: station),
      ),
    );
  }

  void _editStation(StationModel station) async {
    await _cubit.prepareEditForm(station);
    _showFormDialog(station: station);
  }

  void _showStationDetails(StationModel station) {
    context.push('/station-products?id=${station.id}&name=${Uri.encodeComponent(station.name)}&code=${Uri.encodeComponent(station.code)}&type=${station.type}');
  }

  void _showDeleteConfirm(StationModel station) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف "${station.name}"؟', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(dialogContext);
              _cubit.deleteStation(station);
            },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}