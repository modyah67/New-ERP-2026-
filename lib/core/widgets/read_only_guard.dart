import 'package:flutter/material.dart';
import '../services/account_status_service.dart';
import '../services/tenant_service.dart';
import '../theme.dart';

class ReadOnlyGuard {
  static bool get isReadOnly => AccountStatusService().isReadOnly || TenantService().isReadOnly;
  static bool get isFrozen => AccountStatusService().isFrozen || TenantService().isFrozen;
  static bool get isExpired => TenantService().isExpired;
  static bool get isWriteBlocked => isFrozen || isReadOnly || isExpired || !TenantService().canWrite();

  /// فحص فوري متزامن (Synchronous Check)
  static bool check(BuildContext context) {
    if (isFrozen) {
      if (context.mounted) AccountStatusService.showFrozenDialog(context);
      return false;
    }
    if (isReadOnly) {
      if (context.mounted) AccountStatusService.showReadOnlySnackBar(context);
      return false;
    }
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

  /// فحص غير متزامن مع التحقق الحي السريع من السيرفر قبل الحفظ مباشرة
  static Future<bool> checkAsync(BuildContext context) async {
    return AccountStatusService.checkWriteAllowed(context, fastRemoteCheck: true);
  }
}
