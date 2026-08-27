// lib/core/auth_state_notifier.dart
// ─────────────────────────────────────────────
// Shared ValueNotifier that bridges AuthCubit → GoRouter.
// Both can import this file without circular deps.
// ─────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../features/auth/auth_cubit.dart';

/// Global notifier — GoRouter's refreshListenable listens to this.
/// AuthCubit writes to it on every state change.
final ValueNotifier<AuthState> authNotifier =
    ValueNotifier<AuthState>(const AuthInitial());
