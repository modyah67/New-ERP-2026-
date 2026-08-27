import 'package:flutter/widgets.dart';
import '../auth_state_notifier.dart';
import '../../features/auth/auth_cubit.dart';

extension FiscalYearPermissionExtension on BuildContext {
  bool canViewFiscalYear() {
    final authState = authNotifier.value;
    if (authState is AuthAuthenticated) return authState.isAdmin;
    return false;
  }

  bool canManageFiscalYear() {
    final authState = authNotifier.value;
    if (authState is AuthAuthenticated) return authState.isAdmin;
    return false;
  }
}
