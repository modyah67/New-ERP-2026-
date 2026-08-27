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

  bool get isActive {
    if (_localAdminBlocked != null) return !_localAdminBlocked!;
    if (_adminData != null && _adminData!.containsKey('is_active')) {
      return _adminData!['is_active'] == true;
    }
    if (_tenantData != null && _tenantData!.containsKey('is_active')) {
      return _tenantData!['is_active'] == true;
    }
    return true;
  }

  bool get isReadOnly {
    if (_localAdminReadOnly != null) return _localAdminReadOnly!;
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

      // 0. Resolve the organization's owner (admin) user ID
      String ownerUserId = currentUserId;
      try {
        final userRow = await _client.from('users').select('is_admin').eq('id', currentUserId).maybeSingle();
        final isCurrentUserAdmin = userRow?['is_admin'] == true;
        if (!isCurrentUserAdmin) {
          final adminRow = await _client.from('users').select('id').eq('is_admin', true).limit(1).maybeSingle();
          if (adminRow != null && adminRow['id'] != null) {
            ownerUserId = adminRow['id'].toString();
          }
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

      // 2. Validate against Admin Supabase using the owner's user ID
      _adminData = await AdminService().validateSubscription(ownerUserId);

      // 3. If missing from Admin Supabase but has local tenant → auto-register
      if (_adminData == null && _tenantData != null) {
        debugPrint('TenantService: not on Admin Supabase, auto-registering...');
        final user = _client.auth.currentUser;
        if (user != null) {
          final fullName = user.userMetadata?['full_name'] as String? ??
              user.email?.split('@').first ?? 'User';
          final email = user.email ?? '';
          final phone = user.userMetadata?['phone'] as String? ?? '';

          final adminResult = await AdminService().registerTenant(
            userId: ownerUserId,
            fullName: fullName,
            email: email,
            phone: phone,
          );
          if (adminResult != null) {
            debugPrint('TenantService: auto-registered on Admin: ${adminResult['tenant_id']}');
            _adminData = await AdminService().validateSubscription(ownerUserId);
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

    try {
      // Create a separate Supabase client for Admin
      _adminClient = SupabaseClient(
        AdminConfig.supabaseUrl,
        AdminConfig.supabaseAnonKey,
      );

      _tenantChannel = _adminClient!.channel('tenant_$currentTenantId');

      _tenantChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'tenants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: currentTenantId,
            ),
            callback: (payload) async {
              debugPrint('TenantService: Realtime update received!');
              // Reload from Admin Supabase
              final userId = _client.auth.currentUser?.id;
              if (userId != null) {
                _adminData = await AdminService().validateSubscription(userId);
                debugPrint('TenantService: refreshed via Realtime '
                    '(active=$isActive, readOnly=$isReadOnly, expired=$isExpired)');
                onStatusChanged?.call();
              }
            },
          )
          .subscribe();

      debugPrint('TenantService: subscribed to Realtime for tenant $currentTenantId');
    } catch (e) {
      debugPrint('TenantService: Realtime subscription failed: $e');
    }
  }

  /// Unsubscribe from Realtime
  void unsubscribe() {
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
