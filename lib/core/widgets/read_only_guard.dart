import 'package:flutter/material.dart';
import '../../core/services/tenant_service.dart';
import '../../core/theme.dart';

class ReadOnlyGuard {
  /// Checks if write is allowed using cached tenant status.
  /// Tenant status auto-refreshes every 60 seconds via ShellPage timer.
  static bool check(BuildContext context) {
    final tenant = TenantService();
    if (!tenant.isSubscriptionActive) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('الاشتراك غير مفعّل — تواصل مع المالك', style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
              ],
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return false;
    }
    if (!tenant.isActive) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.block, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('الحساب مجمد — تواصل مع الإدارة', style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
              ],
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return false;
    }
    if (tenant.isReadOnly) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('النظام في وضع القراءة فقط', style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
              ],
            ),
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return false;
    }
    if (tenant.isExpired) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.timer_off, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('اشتراكك منتهي — جدد اشتراكك مع الإدارة', style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
              ],
            ),
            backgroundColor: AppTheme.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return false;
    }
    return true;
  }
}
