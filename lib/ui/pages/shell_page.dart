import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/services/tenant_service.dart';
import '../../core/services/account_status_service.dart';
import '../../features/auth/auth_cubit.dart';
import '../../features/dashboard/dashboard_cubit.dart';
import '../../ui/widgets/expandable_sidebar.dart';
import '../widgets/theme_switcher_button.dart';
import '../widgets/safe_image.dart';
import 'home_page.dart';

class ShellPage extends StatefulWidget {
  final Widget? child;

  const ShellPage({super.key, this.child});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  bool _collapsed = false;
  bool _showSubscriptionBanner = true;
  Timer? _timer;
  int _timerSeconds = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
    // Start periodic background sync with Admin Supabase (every 15s)
    TenantService().startPeriodicSync(const Duration(seconds: 15));
    // Listen for real-time status changes from Admin Supabase
    TenantService().onStatusChanged = _handleStatusChange;
    AccountStatusService().statusNotifier.addListener(_handleStatusChange);
  }

  void _handleStatusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    TenantService().stopPeriodicSync();
    TenantService().onStatusChanged = null;
    AccountStatusService().statusNotifier.removeListener(_handleStatusChange);
    super.dispose();
  }

  void _startTimer() {
    _updateTimerSeconds();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimerSeconds();
      if (mounted) setState(() {});
    });
  }

  void _updateTimerSeconds() {
    final tenant = TenantService();
    if (tenant.expiresAt != null) {
      _timerSeconds = tenant.expiresAt!.difference(DateTime.now()).inSeconds;
      if (_timerSeconds < 0) _timerSeconds = 0;
    } else {
      _timerSeconds = 0;
    }
  }

  List<_NavItem> get _adminNavItems => [
        const _NavItem(
            icon: Icons.dashboard_outlined,
            label: 'الرئيسية',
            routePath: '/home',
            alwaysVisible: true),
        const _NavItem(
            icon: Icons.data_usage_outlined,
            label: 'البيانات',
            children: [
              _NavItem(
                  icon: Icons.person_outline,
                  label: 'العملاء',
                  routePath: '/customers'),
              _NavItem(
                  icon: Icons.people_outline,
                  label: 'الموردون',
                  routePath: '/suppliers'),
              _NavItem(
                  icon: Icons.local_shipping,
                  label: 'موردين النقل',
                  routePath: '/transport-suppliers'),
              _NavItem(
                  icon: Icons.factory_outlined,
                  label: 'موردين المحطات',
                  routePath: '/station-suppliers'),
              _NavItem(
                  icon: Icons.assignment_outlined,
                  label: 'موردين التخصيمات',
                  routePath: '/deductions-suppliers'),
              _NavItem(
                  icon: Icons.local_shipping_outlined,
                  label: 'المخلصين',
                  routePath: '/clearing-agents'),
              _NavItem(
                  icon: Icons.flight_outlined,
                  label: 'شركات الشحن',
                  routePath: '/shipping-companies'),
              _NavItem(
                  icon: Icons.person_outline,
                  label: 'المساهمين',
                  routePath: '/shareholders'),
            ]),
        const _NavItem(
            icon: Icons.receipt_long_outlined,
            label: 'كشوفات الحساب',
            children: [
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'كشف حساب العميل',
                  routePath: '/export-customer-statement'),
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'كشف حساب الموردين',
                  routePath: '/supplier-statement-page'),
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'كشف حساب موردين النقل',
                  routePath: '/transport-supplier-statement'),
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'كشف حساب المخلص',
                  routePath: '/clearing-agent-statement'),
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'كشف حساب شركات الشحن',
                  routePath: '/shipping-company-statement'),
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'كشف حساب المساهم',
                  routePath: '/shareholder-statement'),
            ]),
        const _NavItem(
            icon: Icons.account_balance_wallet_outlined,
            label: 'الحسابات',
            children: [
              _NavItem(
                  icon: Icons.account_tree_outlined,
                  label: 'شجرة الحسابات',
                  routePath: '/chart-of-accounts'),
              _NavItem(
                  icon: Icons.account_tree_outlined,
                  label: 'الخزينة الرئيسية',
                  routePath: '/accounts'),
              _NavItem(
                  icon: Icons.account_balance_outlined,
                  label: 'الحسابات البنكية',
                  routePath: '/bank-accounts'),
              _NavItem(
                  icon: Icons.currency_exchange,
                  label: 'أسعار الصرف',
                  routePath: '/exchange-rates'),
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'الشيكات',
                  routePath: '/cheques'),
              _NavItem(
                  icon: Icons.balance_outlined,
                  label: 'الميزان التجريبي',
                  routePath: '/trial-balance'),
              _NavItem(
                  icon: Icons.book_outlined,
                  label: 'دفتر الأستاذ',
                  routePath: '/general-ledger'),
              _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'قيود اليومية',
                  routePath: '/journal-entry'),
              _NavItem(
                  icon: Icons.account_balance_outlined,
                  label: 'الميزانية العامة',
                  routePath: '/balance-sheet'),
              _NavItem(
                  icon: Icons.assessment_outlined,
                  label: 'قائمة الدخل',
                  routePath: '/income-statement'),
              _NavItem(
                  icon: Icons.payments_outlined,
                  label: 'التدفقات النقدية',
                  routePath: '/cash-flow'),
              _NavItem(
                  icon: Icons.event_available_outlined,
                  label: 'السنوات المالية',
                  routePath: '/fiscal-year-closing'),
            ]),
        const _NavItem(
            icon: Icons.warehouse_outlined,
            label: 'المخازن',
            children: [
              _NavItem(
                  icon: Icons.inventory_outlined,
                  label: 'مواد التعبئة',
                  routePath: '/raw-materials'),
              _NavItem(
                  icon: Icons.eco_outlined,
                  label: 'أصناف الفاكهة',
                  routePath: '/fruit-types'),
              _NavItem(
                  icon: Icons.local_shipping_outlined,
                  label: 'المشتريات',
                  routePath: '/purchases'),
              _NavItem(
                  icon: Icons.store_outlined,
                  label: 'المخازن الفرعية',
                  routePath: '/stations'),
              _NavItem(
                  icon: Icons.swap_horiz,
                  label: 'تحويل بين المخازن',
                  routePath: '/transfers'),
              _NavItem(
                  icon: Icons.warehouse_outlined,
                  label: 'متابعة المخازن',
                  routePath: '/warehouse-tracking'),
              _NavItem(
                  icon: Icons.eco_outlined,
                  label: 'شراء المحاصيل',
                  routePath: '/lots'),
              _NavItem(
                  icon: Icons.checklist_outlined,
                  label: 'التعبئة',
                  routePath: '/packing'),
              /*_NavItem(
                  icon: Icons.delete_sweep_outlined,
                  label: 'هالك التعبئة',
                  routePath: '/packing/waste'),*/
              _NavItem(
                  icon: Icons.sort_outlined,
                  label: 'الفرز',
                  routePath: '/sorting'),
              _NavItem(
                  icon: Icons.assignment_return_outlined,
                  label: 'مرتجع المحاصيل',
                  routePath: '/lots/returns'),
            ]),
        const _NavItem(
            icon: Icons.monetization_on_outlined,
            label: 'الفواتير و الارباح',
            children: [
              _NavItem(
                  icon: Icons.public_outlined,
                  label: 'الشحنات التصديرية',
                  routePath: '/exports'),
              _NavItem(
                  icon: Icons.description_outlined,
                  label: 'فواتير مبدئية',
                  routePath: '/proforma-invoices'),
              _NavItem(
                  icon: Icons.trending_up_outlined,
                  label: 'الربحية',
                  routePath: '/exports/profit'),
              _NavItem(
                  icon: Icons.groups_outlined,
                  label: 'توزيع الأرباح',
                  routePath: '/exports/profit-distribution'),
              _NavItem(
                  icon: Icons.pie_chart_outline,
                  label: 'مراكز التكلفه',
                  routePath: '/exports/cost-summary'),
              _NavItem(
                  icon: Icons.settings_outlined,
                  label: 'إدارة تصنيفات التكاليف',
                  routePath: '/exports/cost-categories'),
            ]),
        const _NavItem(
            icon: Icons.people_alt_outlined,
            label: 'إدارة المستخدمين',
            routePath: '/user-management',
            adminOnly: true),
        const _NavItem(
            icon: Icons.backup_outlined,
            label: 'النسخ الاحتياطي',
            routePath: '/backup',
            adminOnly: true),
      ];

  List<_NavItem> get _flatNavItems {
    final list = <_NavItem>[];
    void flatten(List<_NavItem> items) {
      for (var item in items) {
        if (item.children != null && item.children!.isNotEmpty) {
          flatten(item.children!);
        } else {
          list.add(item);
        }
      }
    }

    flatten(_adminNavItems);
    return list;
  }

  bool _getIsAdmin(AuthState authState) {
    if (authState is AuthAuthenticated) {
      return authState.isAdmin;
    }
    return false;
  }

  List<String> _getAllowedPages(AuthState authState) {
    if (authState is AuthAuthenticated) {
      return authState.allowedPages;
    }
    return [];
  }

  List<_NavItem> _filteredNavItems(AuthState authState) {
    final isAdmin = _getIsAdmin(authState);
    final allowedPages = _getAllowedPages(authState);

    if (isAdmin) {
      return _adminNavItems;
    }

    return _flatNavItems.where((item) {
      if (item.adminOnly && !isAdmin) return false;
      if (item.alwaysVisible) return true;
      if (isAdmin) return true;
      if (item.routePath != null && !allowedPages.contains(item.routePath))
        return false;
      return true;
    }).toList();
  }

  String _getCurrentRoute(BuildContext context) {
    try {
      return GoRouterState.of(context).matchedLocation;
    } catch (_) {
      return '/';
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width <= 50 || size.height <= 50) {
      return const SizedBox.shrink();
    }

    final isCompact = size.width < 768;
    final tenant = TenantService();
    final statusService = AccountStatusService();
    final isAccountFrozen = statusService.isFrozen || !tenant.isActive;
    final isAccountReadOnly = statusService.isReadOnly || tenant.isReadOnly;

    // If frozen — show full-screen frozen page
    if (isAccountFrozen) {
      return _buildFrozenPage(tenant);
    }

    // If expired — show full-screen renewal page
    if (tenant.isExpired) {
      return _buildExpiredPage(tenant);
    }

    final body = Row(
      children: [
        if (!isCompact) _buildSidebar(),
        Expanded(
          child: Column(
            children: [
              // Read-only banner
              if (isAccountReadOnly)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  color: const Color(0xFFD97706),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'وضع القراءة فقط مفعّل من قبل الإدارة — لا يمكن إضافة، تعديل أو حذف أي بيانات',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: () async {
                          await AccountStatusService().checkStatus(forceRefresh: true);
                          await TenantService().refreshStatus();
                          if (mounted) setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(45),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white54),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.refresh, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('تحديث الحالة', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo')),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Subscription countdown banner (only on home page)
              if (!tenant.isExpired &&
                  tenant.expiresAt != null &&
                  _getCurrentRoute(context) == '/home')
                _buildSubscriptionBanner(tenant),
              Expanded(child: widget.child ?? const HomePage()),
            ],
          ),
        ),
      ],
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      drawer: isCompact ? _buildDrawer() : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          if (isDark) ...[
            SafeImage(
              'assets/images/login_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF041E42)),
            ),
            Container(
              color: Colors.black.withAlpha(100),
            ),
          ] else ...[
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF8FAFC),
                    Color(0xFFF1F5F9),
                    Color(0xFFE2E8F0),
                  ],
                ),
              ),
            ),
          ],
          // Main content
          isCompact
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    body,
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Builder(
                        builder: (ctx) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0x0DFFFFFF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withAlpha(25)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.menu,
                                    color: Color(0xFF3FD4E8)),
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: ThemeSwitcherButton(),
                    ),
                  ],
                )
              : body,
        ],
      ),
    );
  }

  Widget _buildSubscriptionBanner(TenantService tenant) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppTheme.primary : Colors.black;
    final iconColor = isDark ? AppTheme.primary : const Color(0xFF0284C7);
    final bgColor = isDark ? AppTheme.primary.withAlpha(30) : const Color(0xFFE0F2FE);

    if (!_showSubscriptionBanner) {
      return GestureDetector(
        onTap: () => setState(() => _showSubscriptionBanner = true),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: bgColor,
          child: Icon(Icons.keyboard_arrow_down, color: iconColor, size: 16),
        ),
      );
    }

    final expiry = tenant.expiresAt;
    final dateStr = expiry != null
        ? '${expiry.day.toString().padLeft(2, '0')}/${expiry.month.toString().padLeft(2, '0')}/${expiry.year}'
        : 'غير محدد';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.card_membership_outlined, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Text(
              'اشتراك نشط حتى $dateStr',
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () async {
                await TenantService().loadTenant();
                if (mounted) setState(() {});
              },
              child: Icon(Icons.refresh, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => setState(() => _showSubscriptionBanner = false),
              child: Icon(Icons.keyboard_arrow_up, color: iconColor, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiredPage(TenantService tenant) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1630),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeImage('assets/images/login_bg.png',
              fit: BoxFit.cover, opacity: const AlwaysStoppedAnimation(.15)),
          Container(color: Colors.black.withAlpha(150)),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 440,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0x1E1A2A4A),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withAlpha(25)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_outline,
                            color: AppTheme.danger, size: 48),
                      ),
                      const SizedBox(height: 24),
                      const Text('اشتراكك منتهي',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      Text(
                        'الاشتراك التجريبي انتهى.\nتواصل مع الإدارة لتجديد اشتراكك.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 14,
                            fontFamily: 'Cairo',
                            height: 1.6),
                      ),
                      const SizedBox(height: 32),
                      // Countdown showing time since expiry
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withAlpha(15),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: AppTheme.danger.withAlpha(40)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_off,
                                color: AppTheme.danger, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              'انتهت منذ ${tenant.daysRemaining > 0 ? '${-tenant.daysRemaining} يوم' : '0 يوم'}',
                              style: const TextStyle(
                                  color: AppTheme.danger,
                                  fontSize: 13,
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Refresh button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await TenantService().loadTenant();
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.refresh, size: 20),
                          label: const Text('تحديث الحالة',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Logout button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => context.read<AuthCubit>().signOut(),
                          icon: const Icon(Icons.logout, size: 20),
                          label: const Text('تسجيل الخروج',
                              style:
                                  TextStyle(fontSize: 15, fontFamily: 'Cairo')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withAlpha(40)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrozenPage(TenantService tenant) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1630),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeImage('assets/images/login_bg.png',
              fit: BoxFit.cover, opacity: const AlwaysStoppedAnimation(.15)),
          Container(color: Colors.black.withAlpha(150)),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 440,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0x1E1A2A4A),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withAlpha(25)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.pause_circle_outline,
                            color: Colors.orange, size: 48),
                      ),
                      const SizedBox(height: 24),
                      const Text('الحساب موقوف مؤقتاً',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      Text(
                        'الحساب موقوف مؤقتاً من قبل الإدارة، يرجى التواصل مع الدعم.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 15,
                            fontFamily: 'Cairo',
                            height: 1.6),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await AccountStatusService().checkStatus(forceRefresh: true);
                            await TenantService().loadTenant();
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.refresh, size: 20),
                          label: const Text('تحديث الحالة',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => context.read<AuthCubit>().signOut(),
                          icon: const Icon(Icons.logout, size: 20),
                          label: const Text('تسجيل الخروج',
                              style:
                                  TextStyle(fontSize: 15, fontFamily: 'Cairo')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withAlpha(40)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: 290,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: _buildSidebar(isDrawer: true),
        ),
      ),
    );
  }

  Widget _buildSidebar({bool isDrawer = false}) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        final navItems = _filteredNavItems(authState);
        final currentRoute = _getCurrentRoute(context);
        final collapsed = isDrawer ? false : _collapsed;

        // Build badge counts
        final dashState = context.watch<DashboardCubit>().state;
        final badgeCounts = dashState.badgeCounts;

        SidebarNavItem mapItem(_NavItem item) {
          int? badge;
          Color? badgeColor;
          if (item.routePath == '/exports') {
            badge = badgeCounts['activeShipments'] as int?;
            badgeColor = AppTheme.primary;
          } else if (item.routePath == '/cheques') {
            badge = badgeCounts['alerts'] as int?;
            badgeColor = AppTheme.warning;
          } else if (item.routePath == '/customers') {
            badge = badgeCounts['unpaidInvoices'] as int?;
            badgeColor = AppTheme.danger;
          }

          List<SidebarNavItem>? children;
          if (item.children != null) {
            children = item.children!.map((c) => mapItem(c)).toList();
          }

          return SidebarNavItem(
            icon: item.icon,
            label: item.label,
            routePath: item.routePath,
            adminOnly: item.adminOnly,
            badgeCount: badge,
            badgeColor: badgeColor,
            children: children,
          );
        }

        final sidebarItems = navItems.map((item) => mapItem(item)).toList();

        // User section
        String fullName = 'مستخدم';
        String initial = 'م';
        if (authState is AuthAuthenticated) {
          fullName = authState.fullName ?? authState.email ?? 'مستخدم';
          initial = fullName.isNotEmpty ? fullName.substring(0, 1) : 'م';
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;

        final userSection = Padding(
          padding:
              collapsed ? const EdgeInsets.all(8) : const EdgeInsets.all(12),
          child: collapsed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: fullName,
                      preferBelow: false,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x1AFFFFFF) : const Color(0x140F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Center(
                          child: Text(initial,
                              style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const ThemeSwitcherButton(isCompact: true),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0x1AFFFFFF) : const Color(0x140F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Center(
                        child: Text(initial,
                            style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fullName,
                              style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo'),
                              overflow: TextOverflow.ellipsis),
                          Text('مستخدم',
                              style: TextStyle(
                                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                                  fontSize: 12,
                                  fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                    const ThemeSwitcherButton(),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.logout,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B), size: 22),
                      tooltip: 'تسجيل الخروج',
                      onPressed: () => _confirmLogout(),
                    ),
                  ],
                ),
        );

        return ExpandableSidebar(
          items: sidebarItems,
          currentRoute: currentRoute,
          collapsed: collapsed,
          isGlass: isDrawer ? false : currentRoute == '/home',
          isDrawer: isDrawer,
          onToggleCollapse: isDrawer
              ? () => Navigator.of(context).pop()
              : () => setState(() => _collapsed = !_collapsed),
          headerTitle: AppConstants.appName,
          headerSubtitle: AppConstants.appVersion,
          userSection: userSection,
        );
      },
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
            ),
          ),
          title: Text('تسجيل الخروج',
              style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo')),
          content: Text('هل أنت متأكد؟',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<AuthCubit>().signOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('خروج'),
            ),
          ],
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String? routePath;
  final bool adminOnly;
  final bool alwaysVisible;
  final List<_NavItem>? children;
  const _NavItem(
      {required this.icon,
      required this.label,
      this.routePath,
      this.adminOnly = false,
      this.alwaysVisible = false,
      this.children});
}
