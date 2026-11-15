import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/admin_config.dart';
import '../theme.dart';
import 'tenant_service.dart';

/// الحالات المحتملة لحساب المتجر في الـ ERP
enum AccountStatus {
  active,
  readOnly,
  frozen,
}

/// الخدمة المركزية لإدارة ومراقبة حالة الحساب (Active / Read-Only / Frozen)
/// والربط المباشر مع جدول erp_accounts في Supabase الأدمن المركزي
class AccountStatusService {
  static final AccountStatusService _instance = AccountStatusService._internal();
  factory AccountStatusService() => _instance;
  AccountStatusService._internal();

  static const String _prefsKey = 'erp_account_status_cache';

  final ValueNotifier<AccountStatus> statusNotifier = ValueNotifier<AccountStatus>(AccountStatus.active);
  final StreamController<AccountStatus> _streamController = StreamController<AccountStatus>.broadcast();

  Stream<AccountStatus> get statusStream => _streamController.stream;
  AccountStatus get status => statusNotifier.value;

  bool get isFrozen => status == AccountStatus.frozen;
  bool get isReadOnly => status == AccountStatus.readOnly;
  bool get isActive => status == AccountStatus.active;
  bool get isWriteAllowed => status == AccountStatus.active;

  Timer? _pollingTimer;
  SupabaseClient? _adminRealtimeClient;
  RealtimeChannel? _realtimeChannel;
  bool _isChecking = false;

  /// تهيئة الخدمة عند فتح التطبيق وقراءة الحالة المحفوظة محلياً
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null) {
        final parsed = _parseStatus(cached);
        statusNotifier.value = parsed;
        debugPrint('🛡️ [AccountStatusService] Initialized with cached status: $parsed');
      }
    } catch (e) {
      debugPrint('🛡️ [AccountStatusService] Error loading cached status: $e');
    }

    // بدء المراقبة التلقائية والفحص من السيرفر
    startMonitoring();
    // فحص فوري عند بدء التطبيق
    unawaited(checkStatus());
  }

  /// الفحص المركزي لحالة الحساب من جدول erp_accounts (أو tenants كبديل) في Supabase الأدمن
  Future<AccountStatus> checkStatus({bool forceRefresh = false, String? explicitEmail}) async {
    if (_isChecking && !forceRefresh) return status;
    _isChecking = true;

    try {
      final baseUrl = AdminConfig.supabaseUrl;
      final anonKey = AdminConfig.supabaseAnonKey;
      if (baseUrl.isEmpty || anonKey.isEmpty) {
        debugPrint('🛡️ [AccountStatusService] AdminConfig not configured.');
        return status;
      }

      final headers = {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
      };

      // 1. تحديد البريد الإلكتروني للمتجر أو المالك
      String targetEmail = explicitEmail ?? '';
      if (targetEmail.isEmpty) {
        try {
          final localClient = Supabase.instance.client;
          final currentAuthUser = localClient.auth.currentUser;
          if (currentAuthUser != null && currentAuthUser.email != null) {
            targetEmail = currentAuthUser.email!;
          }

          // إذا كان المستخدم الحالي موظفاً محلياً، نبحث عن إيميل المالك في جدول users
          if (targetEmail.isEmpty || !targetEmail.contains('@') || targetEmail.endsWith('.local')) {
            final adminRow = await localClient.from('users').select('email').eq('is_admin', true).limit(1).maybeSingle();
            if (adminRow != null && adminRow['email'] != null) {
              targetEmail = adminRow['email'].toString();
            }
          }
        } catch (e) {
          debugPrint('🛡️ [AccountStatusService] Local user resolve note: $e');
        }
      }

      Map<String, dynamic>? accountData;

      // 2. البحث أولاً في جدول erp_accounts
      if (targetEmail.isNotEmpty) {
        try {
          final res = await http.get(
            Uri.parse('$baseUrl/rest/v1/erp_accounts?email=eq.${Uri.encodeComponent(targetEmail)}'),
            headers: headers,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final List list = jsonDecode(res.body);
            if (list.isNotEmpty) {
              accountData = list.first as Map<String, dynamic>;
            }
          }
        } catch (e) {
          debugPrint('🛡️ [AccountStatusService] erp_accounts by email error: $e');
        }
      }

      // 3. إذا لم يتم العثور عليه بالإيميل، استعلام أول حساب في erp_accounts (Single-Tenant Mode)
      if (accountData == null) {
        try {
          final res = await http.get(
            Uri.parse('$baseUrl/rest/v1/erp_accounts?limit=1'),
            headers: headers,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final List list = jsonDecode(res.body);
            if (list.isNotEmpty) {
              accountData = list.first as Map<String, dynamic>;
            }
          }
        } catch (e) {
          debugPrint('🛡️ [AccountStatusService] erp_accounts limit=1 error: $e');
        }
      }

      // 4. Fallback إلى جدول tenants للتوافق القديم
      if (accountData == null && targetEmail.isNotEmpty) {
        try {
          final res = await http.get(
            Uri.parse('$baseUrl/rest/v1/tenants?email=eq.${Uri.encodeComponent(targetEmail)}'),
            headers: headers,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final List list = jsonDecode(res.body);
            if (list.isNotEmpty) {
              accountData = list.first as Map<String, dynamic>;
            }
          }
        } catch (_) {}
      }

      if (accountData == null) {
        try {
          final res = await http.get(
            Uri.parse('$baseUrl/rest/v1/tenants?limit=1'),
            headers: headers,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final List list = jsonDecode(res.body);
            if (list.isNotEmpty) {
              accountData = list.first as Map<String, dynamic>;
            }
          }
        } catch (_) {}
      }

      // 5. تحليل البيانات وتحديد الحالة بدقة
      AccountStatus newStatus = AccountStatus.active;
      if (accountData != null) {
        final rawIsActive = accountData['is_active'];
        final rawIsReadOnly = accountData['is_read_only'];
        final rawStatus = accountData['status']?.toString().toLowerCase().trim();

        // 1. التجميد (الأولوية القصوى)
        if (rawIsActive == false ||
            rawStatus == 'frozen' ||
            rawStatus == 'suspended' ||
            rawStatus == 'blocked') {
          newStatus = AccountStatus.frozen;
        }
        // 2. القراءة فقط
        else if (rawIsReadOnly == true ||
            rawStatus == 'read_only' ||
            rawStatus == 'readonly') {
          newStatus = AccountStatus.readOnly;
        }
        // 3. نشط
        else {
          newStatus = AccountStatus.active;
        }
      }

      // 6. تحديث الحالة العامة والتخزين المحلي
      final oldStatus = statusNotifier.value;
      statusNotifier.value = newStatus;

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, newStatus.name);
      } catch (_) {}

      // مزامنة حالة TenantService لضمان توافق كافة أجزاء النظام
      try {
        TenantService().setLocalAdminOverrides(
          isBlocked: newStatus == AccountStatus.frozen,
          readOnlyMode: newStatus == AccountStatus.readOnly,
        );
        TenantService().onStatusChanged?.call();
      } catch (_) {}

      if (oldStatus != newStatus) {
        debugPrint('🛡️ [AccountStatusService] Status changed: $oldStatus ➔ $newStatus');
        _streamController.add(newStatus);
      }

      return newStatus;
    } catch (e) {
      debugPrint('🛡️ [AccountStatusService] checkStatus error: $e');
      return status;
    } finally {
      _isChecking = false;
    }
  }

  /// تشغيل المراقبة التلقائية (Realtime WebSocket + Polling كل 10 ثوانٍ)
  void startMonitoring({Duration interval = const Duration(seconds: 10)}) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) => checkStatus());

    _setupRealtime();
  }

  void _setupRealtime() {
    if (_realtimeChannel != null) return;
    try {
      final baseUrl = AdminConfig.supabaseUrl;
      final anonKey = AdminConfig.supabaseAnonKey;
      if (baseUrl.isEmpty || anonKey.isEmpty) return;

      _adminRealtimeClient = SupabaseClient(baseUrl, anonKey);
      _realtimeChannel = _adminRealtimeClient!.channel('erp_status_guard');

      // الاستماع لأي تعديل على جدول erp_accounts
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'erp_accounts',
        callback: (payload) {
          debugPrint('🛡️ [AccountStatusService] Realtime change detected on erp_accounts!');
          checkStatus(forceRefresh: true);
        },
      );

      // الاستماع أيضاً لجدول tenants
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tenants',
        callback: (payload) {
          debugPrint('🛡️ [AccountStatusService] Realtime change detected on tenants!');
          checkStatus(forceRefresh: true);
        },
      );

      _realtimeChannel!.subscribe();
      debugPrint('🛡️ [AccountStatusService] Subscribed to Admin Supabase Realtime channel.');
    } catch (e) {
      debugPrint('🛡️ [AccountStatusService] Realtime setup error: $e');
    }
  }

  /// إيقاف المراقبة
  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (_realtimeChannel != null) {
      _adminRealtimeClient?.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  static AccountStatus _parseStatus(String str) {
    switch (str.toLowerCase()) {
      case 'frozen':
      case 'suspended':
      case 'blocked':
        return AccountStatus.frozen;
      case 'readonly':
      case 'read_only':
        return AccountStatus.readOnly;
      default:
        return AccountStatus.active;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // ── GUARDS & UI ALERTS ──
  // ════════════════════════════════════════════════════════════════

  /// فحص سريع وشامل قبل أي عملية حفظ مع التحقق الحي لمنع الحفظ في حال تم التجميد مؤخراً
  static Future<bool> checkWriteAllowed(BuildContext context, {bool fastRemoteCheck = true}) async {
    final service = AccountStatusService();

    // 1. فحص محلي فوري
    if (service.isFrozen) {
      if (context.mounted) showFrozenDialog(context);
      return false;
    }
    if (service.isReadOnly) {
      if (context.mounted) showReadOnlySnackBar(context);
      return false;
    }

    // 2. فحص حي وسريع مع السيرفر لضمان أن الأدمن لم يغير الحالة قبل ثوانٍ
    if (fastRemoteCheck) {
      final fresh = await service.checkStatus(forceRefresh: true);
      if (fresh == AccountStatus.frozen) {
        if (context.mounted) showFrozenDialog(context);
        return false;
      }
      if (fresh == AccountStatus.readOnly) {
        if (context.mounted) showReadOnlySnackBar(context);
        return false;
      }
    }

    return true;
  }

  /// فحص فوري بدون انتظار السيرفر (Synchronous Fast Check)
  static bool checkWriteAllowedSync(BuildContext context) {
    final service = AccountStatusService();
    if (service.isFrozen) {
      if (context.mounted) showFrozenDialog(context);
      return false;
    }
    if (service.isReadOnly) {
      if (context.mounted) showReadOnlySnackBar(context);
      return false;
    }
    return true;
  }

  /// إظهار نافذة منبهة (Dialog) عند محاولة العمل أثناء تجميد الحساب
  static void showFrozenDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.danger.withAlpha(120), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.block_rounded, color: AppTheme.danger, size: 28),
            ),
            const SizedBox(width: 12),
            const Text(
              'تنبيه: الحساب موقوف',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: const Text(
          'الحساب موقوف مؤقتاً من قبل الإدارة، يرجى التواصل مع الدعم.',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            height: 1.6,
            color: Color(0xFFE2E8F0),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('تحديث الحالة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final s = await AccountStatusService().checkStatus(forceRefresh: true);
              if (context.mounted) {
                if (s == AccountStatus.frozen) {
                  showFrozenDialog(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم رفع التجميد بنجاح ✓'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                }
              }
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('حسناً', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  /// إظهار تنبيه وضع القراءة فقط
  static void showReadOnlySnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'النظام في وضع القراءة فقط — لا يمكن إضافة أو تعديل أو حفظ البيانات',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFD97706),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
