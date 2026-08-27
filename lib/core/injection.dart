// lib/core/injection.dart
// ─────────────────────────────────────────────
// Dependency Injection container using get_it.
//
// Registration rules:
//   Singleton  → stateless services, repositories
//   Factory    → stateful objects (Cubits, Controllers)
//
// Usage:
//   final repo = sl<AuthRepository>();        // singleton
//   final cubit = sl<AuthCubit>();            // new instance each time
//   sl.registerSingleton<...>(...);           // manual override
// ─────────────────────────────────────────────

import 'package:get_it/get_it.dart';

/// Service Locator shorthand
final sl = GetIt.instance;

/// Reset all registrations (useful for testing)
Future<void> resetDI() async => sl.reset();
