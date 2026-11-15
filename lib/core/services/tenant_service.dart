import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/admin_config.dart';
import 'admin_service.dart';

class TenantService {
  static final TenantService _instance = TenantService._();
  factory TenantService() => _instance;
  TenantService._();

  final _client = Supabase.instance.client;

  // Separate Supabase client for Admin Realtime
  SupabaseClient? _adminClient;
  RealtimeChannel? _tenantChannel;

  Map<String, dynamic>? _tenantData;
  Map<String, dynamic>? get tenantData => _tenantData;

  // From admin Supabase
  Map<String, dynamic>? _adminData;

  // Local admin overrides (from users table — set by non-admin users inheriting admin status)
  bool? _localAdminBlocked;
  bool? _localAdminReadOnly;
  bool? _localAdminSubscriptionActive;

  // Polling timer for periodic sync with Admin Supabase
  Timer? _pollingTimer;

  /// Called when tenant status changes (freeze, read-only, upgrade, etc.)
  VoidCallback? onStatusChanged;

  /// Set local admin overrides for non-admin users
  void setLocalAdminOverrides({bool? isBlocked, bool? readOnlyMode, bool? subscriptionActive}) {
    _localAdminBlocked = isBlocked;
    _localAdminReadOnly = readOnlyMode;
    _localAdminSubscriptionActive = subscriptionActive;
    debugPrint('TenantService: local admin overrides set '
        '(blocked=$isBlocked, readOnly=$readOnlyMode, subscription=$subscriptionActive)');
  }

  /// Start periodic sync with Admin Supabase
  void startPeriodicSync([Duration interval = const Duration(seconds: 15)]) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) {
      refreshStatus();
    });
    debugPrint('TenantService: periodic sync started (interval: ${interval.inSeconds}s)');
  }

  /// Stop periodic sync
  void stopPeriodicSync() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    debugPrint('TenantService: periodic sync stopped');
  }

  /// Refresh tenant status from Admin Supabase and notify listeners on change
  Future<void> refreshStatus() async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final prevActive = isActive;
      final prevReadOnly = isReadOnly;
      final prevExpired = isExpired;

      String ownerUserId = currentUserId;
      String ownerEmail = _client.auth.currentUser?.email ?? '';

      try {
        final userRow = await _client.from('users').select('is_admin, email').eq('id', currentUserId).maybeSingle();
        final isCurrentUserAdmin = userRow?['is_admin'] == true;
        if (!isCurrentUserAdmin) {
          final adminRow = await _client.from('users').select('id, email').eq('is_admin', true).limit(1).maybeSingle();
          if (adminRow != null) {
            ownerUserId = adminRow['id']?.toString() ?? ownerUserId;
            ownerEmail = adminRow['email']?.toString() ?? ownerEmail;
          }
        } else {
          ownerEmail = userRow?['email']?.toString() ?? ownerEmail;
        }
      } catch (e) {
        debugPrint('TenantService: refreshStatus owner resolve notice: $e');
      }

      final freshAdminData = await AdminService().validateSubscription(ownerUserId, email: ownerEmail);
      if (freshAdminData != null) {
        _adminData = freshAdminData;
      }

      final changed = prevActive != isActive ||
          prevReadOnly != isReadOnly ||
          prevExpired != isExpired;

      if (changed) {
        debugPrint('TenantService: Status updated! (active: $prevActive->$isActive, readOnly: $prevReadOnly->$isReadOnly, expired: $prevExpired->$isExpired)');
        onStatusChanged?.call();
      }
    } catch (e) {
      debugPrint('TenantService: refreshStatus error: $e');
    }
  }

  bool get isFrozen => !isActive;

  bool get isActive {
    if (_localAdminBlocked == true) return false;
    if (_adminData != null) {
      if (_adminData!['is_frozen'] == true) return false;
      if (_adminData!.containsKey('is_active')) {
        return _adminData!['is_active'] == true;
      }
    }
    if (_tenantData != null && _tenantData!.containsKey('is_active')) {
      return _tenantData!['is_active'] == true;
    }
    return true;
  }

  bool get isReadOnly {
    if (_localAdminReadOnly == true) return true;
    if (_adminData != null && _adminData!.containsKey('is_read_only')) {
      return _adminData!['is_read_only'] == true;
    }
    if (_tenantData != null && _tenantData!.containsKey('is_read_only')) {
      return _tenantData!['is_read_only'] == true;
    }
    return false;
  }

  bool get isSubscriptionActive => _localAdminSubscriptionActive ?? true;
  String? get tenantId => _adminData?['tenant_id'] ?? _tenantData?['tenant_id'];
  String? get tenantName => _adminData?['tenant_name'] ?? _tenantData?['tenant_name'];
  int get maxUsers => _tenantData?['max_users'] ?? 50;
  String? get planName => _tenantData?['plan_name'];
  String? get planPeriod => _tenantData?['plan_period'];
  bool get hasTenant => _adminData != null || (_tenantData != null && !_tenantData!.containsKey('error'));

  DateTime? get expiresAt {
    final raw = _adminData?['subscription_expires_at'] ?? _tenantData?['subscription_expires_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  bool get isExpired {
    if (_localAdminSubscriptionActive == false) return true;
    if (_adminData != null && _adminData!.containsKey('is_expired')) {
      return _adminData!['is_expired'] == true;
    }
    if (expiresAt != null) return DateTime.now().isAfter(expiresAt!);
    return false;
  }

  int get daysRemaining {
    if (expiresAt == null) return -1;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  bool get isTrial {
    if (_adminData != null) return _adminData!['plan_id'] == null && !isExpired;
    if (_tenantData != null) return _tenantData!['plan_name'] == null && !isExpired;
    return !isExpired;
  }

  Future<void> loadTenant() async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null) {
        _tenantData = null;
        _adminData = null;
        _localAdminBlocked = null;
        _localAdminReadOnly = null;
        _localAdminSubscriptionActive = null;
        return;
      }

      // 0. Resolve the organization's owner (admin) user ID and email
      final currentUser = _client.auth.currentUser;
      String ownerUserId = currentUserId;
      String ownerEmail = currentUser?.email ?? '';
      try {
        final userRow = await _client.from('users').select('is_admin, email').eq('id', currentUserId).maybeSingle();
        final isCurrentUserAdmin = userRow?['is_admin'] == true;
        if (!isCurrentUserAdmin) {
          final adminRow = await _client.from('users').select('id, email').eq('is_admin', true).limit(1).maybeSingle();
          if (adminRow != null) {
            ownerUserId = adminRow['id']?.toString() ?? ownerUserId;
            ownerEmail = adminRow['email']?.toString() ?? ownerEmail;
          }
        } else {
          ownerEmail = userRow?['email']?.toString() ?? ownerEmail;
        }
      } catch (e) {
        debugPrint('TenantService: resolve ownerUserId failed: $e');
      }

      // 1. Try local ERP tenant first
      try {
        final result = await _client.rpc('get_my_tenant');
        if (result is Map<String, dynamic> && !result.containsKey('error')) {
          _tenantData = result;
        } else {
          _tenantData = null;
        }
      } catch (e) {
        debugPrint('TenantService: local tenant load failed: $e');
        _tenantData = null;
      }

      // 2. Validate against Admin Supabase using the owner's user ID and email
      _adminData = await AdminService().validateSubscription(ownerUserId, email: ownerEmail);

      // 3. If missing from Admin Supabase but has local tenant → auto-register
      if (_adminData == null && _tenantData != null) {
        debugPrint('TenantService: not on Admin Supabase, auto-registering...');
        if (currentUser != null) {
          final fullName = currentUser.userMetadata?['full_name'] as String? ??
              currentUser.email?.split('@').first ?? 'User';
          final email = currentUser.email ?? '';
          final phone = currentUser.userMetadata?['phone'] as String? ?? '';

          final adminResult = await AdminService().registerTenant(
            userId: ownerUserId,
            fullName: fullName,
            email: email,
            phone: phone,
          );
          if (adminResult != null) {
            debugPrint('TenantService: auto-registered on Admin: ${adminResult['tenant_id']}');
            _adminData = await AdminService().validateSubscription(ownerUserId, email: email);
          }
        }
      }

      // 4. Fallback for single-company testing (if no tenant mapping exists)
      if (_tenantData == null && _adminData == null) {
        debugPrint('TenantService: No tenant found. Attempting single-company fallback from sys_companies...');
        try {
          final fallbackCompany = await _client.from('sys_companies').select().limit(1).maybeSingle();
          if (fallbackCompany != null) {
            _tenantData = {
              'tenant_id': fallbackCompany['id'],
              'tenant_name': fallbackCompany['name'],
              'is_active': true,
              'is_read_only': false,
              'max_users': 50,
              'plan_name': 'Single Company Mode',
              // Set expiration 10 years in the future to keep UI happy
              'subscription_expires_at': DateTime.now().add(const Duration(days: 3650)).toIso8601String(),
            };
            debugPrint('TenantService: Single-company fallback successful for ${fallbackCompany['name']} (${fallbackCompany['id']})');
          }
        } catch (e, stackTrace) {
          debugPrint('===================================================');
          debugPrint('TenantService: Single-company fallback failed: $e');
          debugPrint('StackTrace: $stackTrace');
          debugPrint('===================================================');
        }
      }

      debugPrint('TenantService: loaded tenant "${tenantName ?? 'unknown'}" '
          '(active=$isActive, readOnly=$isReadOnly, '
          'local=${_tenantData != null}, admin=${_adminData != null}, '
          'expired=$isExpired, trial=$isTrial)');

      // 3. Subscribe to Realtime after first successful load
      _subscribeToTenantChanges();
    } catch (e) {
      debugPrint('TenantService: error loading tenant: $e');
      _tenantData = null;
      _adminData = null;
    }
  }

  /// Subscribe to real-time changes on Admin Supabase's tenants table
  void _subscribeToTenantChanges() {
    final currentTenantId = tenantId;
    if (currentTenantId == null) return;

    // Don't re-subscribe if already listening
    if (_tenantChannel != null) return;

    if (!AdminService().isConfigured) {
      debugPrint('TenantService: Admin Supabase anon key not configured, skipping Realtime subscription.');
      return;
    }

    try {
      // Create a separate Supabase client for Admin
      _adminClient = SupabaseClient(
        AdminConfig.supabaseUrl,
        AdminConfig.supabaseAnonKey,
      );

      _tenantChannel = _adminClient!.channel('tenant_$currentTenantId');

      _tenantChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: AdminConfig.accountsTable,
            callback: (payload) async {
              debugPrint('TenantService: Realtime update on accounts received: ${payload.eventType}');
              await refreshStatus();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: AdminConfig.legacyAccountsTable,
            callback: (payload) async {
              debugPrint('TenantService: Realtime update on legacy tenants received: ${payload.eventType}');
              await refreshStatus();
            },
          )
          .subscribe();

      debugPrint('TenantService: subscribed to Realtime for tenant $currentTenantId');
    } catch (e) {
      debugPrint('TenantService: Realtime subscription failed: $e');
    }
  }

  /// Unsubscribe from Realtime and stop background polling
  void unsubscribe() {
    stopPeriodicSync();
    if (_tenantChannel != null) {
      _adminClient?.removeChannel(_tenantChannel!);
      _tenantChannel = null;
      debugPrint('TenantService: unsubscribed from Realtime');
    }
  }

  Future<void> enforceWriteAllowed() async {
    if (isReadOnly) {
      throw Exception('النظام في وضع القراءة فقط — لا يمكن إجراء تعديلات');
    }
    if (!isActive) {
      throw Exception('الحساب مجمد — تواصل مع الإدارة');
    }
    if (isExpired) {
      throw Exception('اشتراكك منتهي — جدد اشتراكك مع الإدارة');
    }
  }

  bool canWrite() {
    return !isReadOnly && isActive && !isExpired;
  }

  Map<String, dynamic> getTrialInfo() {
    return {
      'is_trial': isTrial,
      'is_expired': isExpired,
      'days_remaining': daysRemaining,
      'expires_at': expiresAt?.toIso8601String(),
      'plan_name': planName,
    };
  }
}
