import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/admin_config.dart';

class AdminService {
  static final AdminService _instance = AdminService._();
  factory AdminService() => _instance;
  AdminService._();

  final _baseUrl = AdminConfig.supabaseUrl;
  final _anonKey = AdminConfig.supabaseAnonKey;

  /// Check whether the Admin Supabase credentials have been properly set
  bool get isConfigured =>
      _baseUrl.isNotEmpty &&
      _anonKey.isNotEmpty &&
      !_anonKey.contains('[') &&
      !_anonKey.contains('YOUR_');

  Map<String, String> get _headers => {
    'apikey': _anonKey,
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_anonKey',
  };

  /// Register a new tenant on the Admin Supabase
  Future<Map<String, dynamic>?> registerTenant({
    required String userId,
    required String fullName,
    required String email,
    required String phone,
  }) async {
    if (!isConfigured) {
      debugPrint('AdminService: Admin Supabase anon key is not configured yet.');
      return null;
    }
    try {
      // 0. Check if tenant already exists
      final checkRes = await http.get(
        Uri.parse('$_baseUrl/rest/v1/tenants?email=eq.${Uri.encodeComponent(email)}'),
        headers: _headers,
      );
      if (checkRes.statusCode == 200) {
        final existing = jsonDecode(checkRes.body) as List;
        if (existing.isNotEmpty) {
          debugPrint('AdminService: tenant already exists for email $email');
          final tenant = existing.first as Map<String, dynamic>;
          final tenantId = tenant['id'];

          // Best-effort link to users and tenant_users
          try {
            await http.post(
              Uri.parse('$_baseUrl/rest/v1/users'),
              headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
              body: jsonEncode({
                'id': userId,
                'full_name': fullName,
                'email': email,
                'phone': phone,
                'is_admin': false,
              }),
            );
            await http.post(
              Uri.parse('$_baseUrl/rest/v1/tenant_users'),
              headers: _headers,
              body: jsonEncode({
                'tenant_id': tenantId,
                'user_id': userId,
                'role': 'owner',
              }),
            );
          } catch (_) {}

          return {
            'tenant_id': tenantId,
            'trial_days': 7,
            'expires_at': tenant['subscription_expires_at'],
          };
        }
      }

      // 1. Insert tenant
      final tenantRes = await http.post(
        Uri.parse('$_baseUrl/rest/v1/tenants'),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode({
          'name': 'متجر $fullName',
          'email': email,
          'tenant_type': 'erp',
          'is_active': true,
          'is_read_only': false,
          'max_users': 50,
          'current_users': 1,
        }),
      );

      if (tenantRes.statusCode != 201 && tenantRes.statusCode != 200) {
        debugPrint('AdminService: tenant insert failed: ${tenantRes.body}');
        return null;
      }

      final tenants = jsonDecode(tenantRes.body) as List;
      if (tenants.isEmpty) return null;
      final tenant = tenants.first;
      final tenantId = tenant['id'];

      // 2. Get trial days AND minutes from settings
      int trialDays = 7;
      int trialMinutes = 0;
      try {
        final settingsRes = await http.get(
          Uri.parse('$_baseUrl/rest/v1/system_settings?select=setting_key,setting_value'),
          headers: _headers,
        );
        if (settingsRes.statusCode == 200) {
          final settings = jsonDecode(settingsRes.body) as List;
          for (final s in settings) {
            if (s['setting_key'] == 'trial_days') {
              trialDays = int.tryParse(s['setting_value'] ?? '7') ?? 7;
            } else if (s['setting_key'] == 'trial_minutes') {
              trialMinutes = int.tryParse(s['setting_value'] ?? '0') ?? 0;
            }
          }
        }
        if (settingsRes.statusCode != 200) {
          debugPrint('AdminService: settings fetch failed (${settingsRes.statusCode}), using defaults');
        }
      } catch (e) {
        debugPrint('AdminService: settings fetch error: $e, using defaults');
      }

      // Safety: trial must be at least 0 (0 days + N minutes is valid)
      debugPrint('AdminService: trial configured as ${trialDays}d ${trialMinutes}m');

      // 3. Set subscription expiry
      final expiresAt = DateTime.now().add(Duration(days: trialDays, minutes: trialMinutes));
      await http.patch(
        Uri.parse('$_baseUrl/rest/v1/tenants?id=eq.$tenantId'),
        headers: _headers,
        body: jsonEncode({
          'subscription_expires_at': expiresAt.toUtc().toIso8601String(),
        }),
      );

      // 4. Insert into admin's users table FIRST (tenant_users FK depends on users.id)
      await http.post(
        Uri.parse('$_baseUrl/rest/v1/users'),
        headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode({
          'id': userId,
          'full_name': fullName,
          'email': email,
          'phone': phone,
          'is_admin': false,
        }),
      );

      // 5. Link user to tenant
      await http.post(
        Uri.parse('$_baseUrl/rest/v1/tenant_users'),
        headers: _headers,
        body: jsonEncode({
          'tenant_id': tenantId,
          'user_id': userId,
          'role': 'owner',
        }),
      );

      debugPrint('AdminService: tenant registered successfully: $tenantId');
      return {
        'tenant_id': tenantId,
        'trial_days': trialDays,
        'expires_at': expiresAt.toIso8601String(),
      };
    } catch (e) {
      debugPrint('AdminService: registerTenant error: $e');
      return null;
    }
  }

  /// Validate subscription status from Admin Supabase
  Future<Map<String, dynamic>?> validateSubscription(String userId, {String? email}) async {
    if (!isConfigured) {
      debugPrint('AdminService: Admin Supabase anon key is not configured yet.');
      return null;
    }
    try {
      Map<String, dynamic>? tenantData;

      // 1. First try resolving via tenant_users
      try {
        final res = await http.get(
          Uri.parse('$_baseUrl/rest/v1/tenant_users?user_id=eq.$userId&select=tenant_id,tenants(*)'),
          headers: _headers,
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as List;
          if (data.isNotEmpty && data.first['tenants'] != null) {
            tenantData = data.first['tenants'] as Map<String, dynamic>;
          }
        }
      } catch (e) {
        debugPrint('AdminService: tenant_users lookup notice: $e');
      }

      // 2. Direct lookup in erp_accounts then tenants by email
      if (tenantData == null && email != null && email.isNotEmpty) {
        for (final tbl in [AdminConfig.accountsTable, AdminConfig.legacyAccountsTable]) {
          try {
            final emailRes = await http.get(
              Uri.parse('$_baseUrl/rest/v1/$tbl?email=eq.${Uri.encodeComponent(email)}'),
              headers: _headers,
            );
            if (emailRes.statusCode == 200) {
              final data = jsonDecode(emailRes.body) as List;
              if (data.isNotEmpty) {
                tenantData = data.first as Map<String, dynamic>;
                break;
              }
            }
          } catch (e) {
            debugPrint('AdminService: direct $tbl email lookup notice: $e');
          }
        }
      }

      // 3. Resilient fallback: fetch from erp_accounts or tenants (limit 1)
      if (tenantData == null) {
        for (final tbl in [AdminConfig.accountsTable, AdminConfig.legacyAccountsTable]) {
          try {
            final fallbackRes = await http.get(
              Uri.parse('$_baseUrl/rest/v1/$tbl?limit=1'),
              headers: _headers,
            );
            if (fallbackRes.statusCode == 200) {
              final data = jsonDecode(fallbackRes.body) as List;
              if (data.isNotEmpty) {
                tenantData = data.first as Map<String, dynamic>;
                break;
              }
            }
          } catch (_) {}
        }
      }

      if (tenantData == null) return null;

      var expiresAt = tenantData['subscription_expires_at'] != null
          ? DateTime.tryParse(tenantData['subscription_expires_at'].toString())
          : null;

      final rawStatus = tenantData['status']?.toString().toLowerCase().trim();
      final rawIsActive = tenantData['is_active'];
      final rawIsReadOnly = tenantData['is_read_only'];

      final bool isFrozen = rawStatus == 'frozen' ||
          rawStatus == 'suspended' ||
          rawStatus == 'blocked' ||
          rawIsActive == false;

      final bool isActive = !isFrozen;

      final bool isReadOnly = rawStatus == 'read_only' ||
          rawStatus == 'readonly' ||
          rawIsReadOnly == true;

      final isExpired = expiresAt != null && DateTime.now().isAfter(expiresAt);

      final daysLeft = expiresAt != null ? expiresAt.difference(DateTime.now()).inDays : -1;

      return {
        'tenant_id': tenantData['id'],
        'tenant_name': tenantData['name'],
        'is_active': isActive,
        'is_read_only': isReadOnly,
        'is_frozen': isFrozen,
        'status': isFrozen ? 'frozen' : (isReadOnly ? 'read_only' : (isExpired ? 'expired' : 'active')),
        'is_expired': isExpired,
        'plan_id': tenantData['plan_id'],
        'days_remaining': daysLeft < 0 ? 0 : daysLeft,
        'subscription_expires_at': tenantData['subscription_expires_at'],
      };
    } catch (e) {
      debugPrint('AdminService: validateSubscription error: $e');
      return null;
    }
  }
}
