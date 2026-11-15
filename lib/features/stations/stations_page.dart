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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isMobile, isDark),
              const SizedBox(height: 20),
              _buildSearchBar(isDark),
              const SizedBox(height: 16),
              Expanded(child: _buildContent(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.accent.withValues(alpha: 0.1) : const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.accent.withValues(alpha: 0.25) : const Color(0xFFBAE6FD),
            ),
          ),
          child: Icon(
            Icons.store_outlined,
            color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المخازن',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 22 : 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    fontFamily: 'Cairo',
                  ),
                ),
                BlocBuilder<StationCubit, StationState>(
                  buildWhen: (prev, curr) => curr is StationLoaded,
                  builder: (context, state) {
                    final count = state is StationLoaded ? state.stations.length : 0;
                    return Text(
                      '$count محطة',
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.refresh_outlined, color: isDark ? null : Colors.black),
          tooltip: 'تحديث',
          onPressed: () => _cubit.loadAll(reset: true),
        ),
        const SizedBox(width: 4),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            isMobile ? 'إضافة' : 'إضافة محطة',
            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            await _cubit.prepareAddForm();
            _showFormDialog();
          },
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    if (isDark) {
      return TextField(
        onChanged: _cubit.onSearchChanged,
        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          hintText: 'بحث بالكود أو الاسم...',
          hintStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
          suffixIcon: BlocBuilder<StationCubit, StationState>(
            buildWhen: (prev, curr) => curr is StationLoaded,
            builder: (context, state) {
              final query = state is StationLoaded ? state.searchQuery : '';
              if (query.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                onPressed: () => _cubit.onSearchChanged(''),
              );
            },
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: _cubit.onSearchChanged,
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          hintText: 'بحث بالكود أو الاسم...',
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Cairo'),
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black54),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: BlocBuilder<StationCubit, StationState>(
            buildWhen: (prev, curr) => curr is StationLoaded,
            builder: (context, state) {
              final query = state is StationLoaded ? state.searchQuery : '';
              if (query.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Colors.black54),
                onPressed: () => _cubit.onSearchChanged(''),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
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
                Text(
                  state.message,
                  style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: () => _cubit.loadAll(reset: true),
                ),
              ],
            ),
          );
        }
        if (state is StationLoaded) {
          if (state.stations.isEmpty) {
            return _buildEmptyState(state.searchQuery, isDark);
          }
          return _buildGridView(state, isDark);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildGridView(StationLoaded state, bool isDark) {
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
        return _buildStationCard(state.stations[index], index, isMobile: isMobile, isDark: isDark);
      },
    );
  }

  Widget _buildStationCard(StationModel station, int index, {bool isMobile = false, required bool isDark}) {
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
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0x3805192D) : Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
          border: Border.all(
            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
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
                          color: isDark ? AppTheme.accent.withValues(alpha: 0.12) : const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                          border: Border.all(
                            color: isDark ? AppTheme.accent.withValues(alpha: 0.25) : const Color(0xFFBAE6FD),
                          ),
                        ),
                        child: Icon(
                          Icons.location_on_outlined,
                          color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                          size: isMobile ? 18 : 22,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: station.isActive
                              ? (isDark ? AppTheme.success.withValues(alpha: 0.1) : const Color(0xFFDCFCE7))
                              : (isDark ? AppTheme.danger.withValues(alpha: 0.1) : const Color(0xFFFEE2E2)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: station.isActive
                                ? (isDark ? Colors.transparent : const Color(0xFF86EFAC))
                                : (isDark ? Colors.transparent : const Color(0xFFFCA5A5)),
                          ),
                        ),
                        child: Text(
                          station.isActive ? 'نشط' : 'غير نشط',
                          style: TextStyle(
                            fontSize: isMobile ? 8 : 9,
                            fontWeight: FontWeight.bold,
                            color: station.isActive
                                ? (isDark ? AppTheme.success : const Color(0xFF16A34A))
                                : AppTheme.danger,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: station.isMain
                          ? (isDark ? AppTheme.primary.withValues(alpha: 0.1) : const Color(0xFFE0F2FE))
                          : (isDark ? AppTheme.accent.withValues(alpha: 0.1) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: station.isMain
                            ? (isDark ? Colors.transparent : const Color(0xFFBAE6FD))
                            : (isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                      ),
                    ),
                    child: Text(
                      station.isMain ? 'رئيسي' : 'فرعي',
                      style: TextStyle(
                        fontSize: isMobile ? 8 : 9,
                        fontWeight: FontWeight.bold,
                        color: station.isMain
                            ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                            : (isDark ? AppTheme.accent : Colors.black),
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    station.name,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.accent.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: isDark ? null : Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Text(
                      station.code,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isMobile ? 10 : 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.accent : Colors.black,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (station.description != null && station.description!.isNotEmpty) ...[
                    Text(
                      station.description!,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isMobile ? 10 : 11,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      _buildQuickAction(
                        Icons.visibility_outlined,
                        AppTheme.primary,
                        'عرض التفاصيل',
                        () => _showStationDetails(station),
                        isMobile: isMobile,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickAction(
                        Icons.edit_outlined,
                        AppTheme.accent,
                        'تعديل',
                        () => _editStation(station),
                        isMobile: isMobile,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickAction(
                        Icons.delete_outline,
                        AppTheme.danger,
                        'حذف',
                        () => _showDeleteConfirm(station),
                        isMobile: isMobile,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, Color color, String tooltip, VoidCallback onTap, {bool isMobile = false, required bool isDark}) {
    final size = isMobile ? 26.0 : 32.0;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? color.withValues(alpha: 0.1) : const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            border: Border.all(
              color: isDark ? color.withValues(alpha: 0.2) : const Color(0xFFBAE6FD),
            ),
          ),
          child: Icon(
            icon,
            size: isMobile ? 14 : 16,
            color: isDark ? color : const Color(0xFF0284C7),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String searchQuery, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_mall_directory_outlined, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty ? 'لا توجد محطات بعد' : 'لا توجد نتائج للبحث',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : Colors.black,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty ? 'اضغط "إضافة محطة" لإضافة أول محطة' : 'جرب كلمة بحث مختلفة',
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo',
              fontSize: 13,
            ),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة محطة', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF05192D) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        title: Text(
          'تأكيد الحذف',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'هل أنت متأكد من حذف "${station.name}"؟',
          style: TextStyle(
            color: isDark ? AppTheme.textSecondary : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'إلغاء',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(dialogContext);
              _cubit.deleteStation(station);
            },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}