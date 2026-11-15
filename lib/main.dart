// lib/main.dart
// ─────────────────────────────────────────────
// Application entry point.
//
// Initialization order:
//   1. Flutter bindings
//   2. Supabase
//   3. App settings
//   4. Dependency Injection (get_it)
//   5. runApp
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/injection.dart';
import 'core/service_module.dart';
import 'core/router.dart';
import 'core/services/account_status_service.dart';
import 'core/theme.dart';
import 'core/theme_cubit.dart';
import 'core/constants.dart';
import 'data/dao/settings_dao.dart';
import 'features/auth/auth_cubit.dart';
import 'features/dashboard/dashboard_cubit.dart';
import 'data/dao/dashboard_dao.dart';

import 'supabase_options.dart';

class _NoPersistenceLocalStorage extends LocalStorage {
  const _NoPersistenceLocalStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => false;

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<void> removePersistedSession() async {}

  @override
  Future<void> persistSession(String persistSessionString) async {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Supabase (without disk session persistence - requires login each launch) ──
  await Supabase.initialize(
    url: SupabaseOptions.url,
    publishableKey: SupabaseOptions.anonKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: _NoPersistenceLocalStorage(),
    ),
  );

  // ── 2. App settings ──
  try {
    final settings = await SettingsDao().getAllSettings();

    if (settings.containsKey('company_name')) {
      AppConstants.companyName = settings['company_name']!;
    }

    if (settings.containsKey('company_address')) {
      AppConstants.companyAddress = settings['company_address']!;
    }

    if (settings.containsKey('company_phone')) {
      AppConstants.companyPhone = settings['company_phone']!;
    }
  } catch (_) {
    // Continue with defaults
  }

  // ── 2b. Seed test data (debug only) ──
  // if (kDebugMode) {
  //   await seedDKLShipment();
  // }

  // ── 3. Dependency Injection ──
  registerDependencies();

  // ── 3b. Initialize Account Status Service (Frozen / ReadOnly check from Admin Supabase) ──
  try {
    await AccountStatusService().init();
  } catch (e) {
    debugPrint('AccountStatusService init error: $e');
  }

  // ── 4. Router ──
  final router = createRouter();

  runApp(AccountingApp(router: router));
}

class AccountingApp extends StatefulWidget {
  final GoRouter router;

  const AccountingApp({
    super.key,
    required this.router,
  });

  @override
  State<AccountingApp> createState() => _AccountingAppState();
}

class _AccountingAppState extends State<AccountingApp>
    with WidgetsBindingObserver {
  late final AuthCubit _authCubit;
  late final DashboardCubit _dashboardCubit;
  late final ThemeCubit _themeCubit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authCubit = sl<AuthCubit>()..checkInitialAuth();
    _dashboardCubit = DashboardCubit(DashboardDao());
    _themeCubit = ThemeCubit()..loadTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authCubit.close();
    _dashboardCubit.close();
    _themeCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>.value(
      value: _authCubit,
      child: BlocProvider<DashboardCubit>.value(
        value: _dashboardCubit,
        child: BlocProvider<ThemeCubit>.value(
          value: _themeCubit,
          child: BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (context, themeMode) {
              final isDark = themeMode == ThemeMode.dark;
              return MaterialApp.router(
                title: 'نظام المحاسبة',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,
                locale: const Locale('ar', 'EG'),
                supportedLocales: const [
                  Locale('ar', 'EG'),
                  Locale('en', 'US'),
                ],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                routerConfig: widget.router,
                builder: (context, child) {
                  return ColoredBox(
                    color: isDark ? const Color(0xFF0F1A2E) : const Color(0xFFF8FAFC),
                    child: SafeArea(
                      child: child!,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
