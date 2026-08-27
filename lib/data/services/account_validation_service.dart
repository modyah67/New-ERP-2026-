import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Unified account validation service.
/// All validation rules in one place — used by Dart, DAO, and RPC.
class AccountValidationService {
  final _client = Supabase.instance.client;
  static final AccountValidationService _instance = AccountValidationService._();
  factory AccountValidationService() => _instance;
  AccountValidationService._();

  static const _validTypes = ['asset', 'liability', 'equity', 'revenue', 'expense'];

  String? validateCode(String code) {
    if (code.trim().isEmpty) return 'كود الحساب مطلوب';
    if (code.length < 3) return 'كود الحساب يجب أن يكون 3 أحرف على الأقل';
    if (!RegExp(r'^[0-9]+$').hasMatch(code)) return 'كود الحساب يجب أن أرقام فقط';
    return null;
  }

  String? validateName(String name) {
    if (name.trim().isEmpty) return 'اسم الحساب مطلوب';
    if (name.trim().length < 2) return 'اسم الحساب قصير جداً';
    return null;
  }

  String? validateType(String type) {
    if (!_validTypes.contains(type)) return 'نوع الحساب غير صالح';
    return null;
  }

  Future<bool> codeExists(String code, {String? excludeId}) async {
    try {
      var query = _client
          .from('accounts')
          .select('id')
          .eq('account_code', code);
      if (excludeId != null) {
        query = query.neq('id', excludeId);
      }
      final data = await query.limit(1);
      return (data as List).isNotEmpty;
    } catch (e) {
      debugPrint('AccountValidation.codeExists error: $e');
      return false;
    }
  }

  Future<bool> hasChildren(String parentId) async {
    try {
      final data = await _client
          .from('accounts')
          .select('id')
          .eq('parent_id', parentId)
          .limit(1);
      return (data as List).isNotEmpty;
    } catch (e) {
      debugPrint('AccountValidation.hasChildren error: $e');
      return false;
    }
  }

  Future<bool> isSystemAccount(String accountId) async {
    try {
      final data = await _client
          .from('accounts')
          .select('is_system')
          .eq('id', int.parse(accountId))
          .maybeSingle();
      return data?['is_system'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isLeafAccount(String accountId) async {
    try {
      final data = await _client
          .from('accounts')
          .select('is_leaf')
          .eq('id', int.parse(accountId))
          .maybeSingle();
      return data?['is_leaf'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isActiveAccount(String accountId) async {
    try {
      final data = await _client
          .from('accounts')
          .select('is_active')
          .eq('id', int.parse(accountId))
          .maybeSingle();
      return data?['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Validate account deletion using the generic SQL function.
  /// Returns [AccountDeletionResult] with action recommendation.
  Future<AccountDeletionResult> validateDeletion(String accountId) async {
    try {
      final result = await _client
          .rpc('fn_validate_account_deletion_v2', params: {
        'p_account_id': int.tryParse(accountId),
      });

      final data = result as Map<String, dynamic>;
      final allowed = data['allowed'] == true;
      final action = data['action'] as String? ?? 'none';
      final reason = data['reason'] as String?;
      final references = data['references'] as List<dynamic>? ?? [];

      return AccountDeletionResult(
        allowed: allowed,
        action: action,
        reason: reason,
        references: references
            .map((r) => AccountReference(
                  table: r['table'] as String,
                  column: r['column'] as String,
                  rowCount: (r['row_count'] as num?)?.toInt() ?? 0,
                ))
            .toList(),
      );
    } catch (e) {
      debugPrint('AccountValidation.validateDeletion error: $e');
      return AccountDeletionResult(
        allowed: false,
        action: 'none',
        reason: 'خطأ في التحقق: $e',
      );
    }
  }

  /// Discover all FK references to an account (generic, no hardcoded tables).
  Future<List<AccountReference>> discoverReferences(String accountId) async {
    try {
      final result = await _client
          .rpc('fn_discover_account_references', params: {
        'p_account_id': int.tryParse(accountId),
      });

      final data = result as List<dynamic>;
      return data
          .map((r) => AccountReference(
                table: r['table'] as String,
                column: r['column'] as String,
                rowCount: (r['row_count'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    } catch (e) {
      debugPrint('AccountValidation.discoverReferences error: $e');
      return [];
    }
  }

  /// Archive an account (soft delete).
  Future<AccountActionResult> archiveAccount(String accountId) async {
    try {
      final result = await _client
          .rpc('fn_archive_account', params: {
        'p_account_id': int.tryParse(accountId),
      });

      final data = result as Map<String, dynamic>;
      return AccountActionResult(
        success: data['success'] == true,
        action: data['action'] as String? ?? 'archive',
        message: data['message'] as String? ?? data['reason'] as String?,
      );
    } catch (e) {
      debugPrint('AccountValidation.archiveAccount error: $e');
      return AccountActionResult(
        success: false,
        action: 'archive',
        message: 'خطأ في الأرشفة: $e',
      );
    }
  }

  /// Restore an archived account.
  Future<AccountActionResult> restoreAccount(String accountId) async {
    try {
      final result = await _client
          .rpc('fn_restore_account', params: {
        'p_account_id': int.tryParse(accountId),
      });

      final data = result as Map<String, dynamic>;
      return AccountActionResult(
        success: data['success'] == true,
        action: data['action'] as String? ?? 'restore',
        message: data['message'] as String? ?? data['reason'] as String?,
      );
    } catch (e) {
      debugPrint('AccountValidation.restoreAccount error: $e');
      return AccountActionResult(
        success: false,
        action: 'restore',
        message: 'خطأ في الاستعادة: $e',
      );
    }
  }

  /// Permanent delete (only for accounts with zero references).
  Future<AccountActionResult> permanentDeleteAccount(String accountId) async {
    try {
      final result = await _client
          .rpc('fn_permanent_delete_account', params: {
        'p_account_id': int.tryParse(accountId),
      });

      final data = result as Map<String, dynamic>;
      return AccountActionResult(
        success: data['success'] == true,
        action: data['action'] as String? ?? 'permanent_delete',
        message: data['message'] as String? ?? data['reason'] as String?,
      );
    } catch (e) {
      debugPrint('AccountValidation.permanentDeleteAccount error: $e');
      return AccountActionResult(
        success: false,
        action: 'permanent_delete',
        message: 'خطأ في الحذف: $e',
      );
    }
  }

  /// Unified account action: delete / archive / restore / permanent_delete.
  Future<AccountActionResult> performAction(String action, String accountId) async {
    try {
      final result = await _client
          .rpc('fn_account_action', params: {
        'p_action': action,
        'p_account_id': int.tryParse(accountId),
      });

      final data = result as Map<String, dynamic>;
      return AccountActionResult(
        success: data['success'] == true || data['allowed'] == true,
        action: data['action'] as String? ?? action,
        message: data['message'] as String? ?? data['reason'] as String?,
      );
    } catch (e) {
      debugPrint('AccountValidation.performAction error: $e');
      return AccountActionResult(
        success: false,
        action: action,
        message: 'خطأ في التنفيذ: $e',
      );
    }
  }
}

// ── Result Models ──

class AccountDeletionResult {
  final bool allowed;
  final String action; // 'delete', 'archive', 'restore', 'none'
  final String? reason;
  final List<AccountReference> references;

  const AccountDeletionResult({
    required this.allowed,
    required this.action,
    this.reason,
    this.references = const [],
  });

  bool get canHardDelete => allowed && action == 'delete';
  bool get canArchive => !allowed && action == 'archive';
  bool get canRestore => action == 'restore';
}

class AccountReference {
  final String table;
  final String column;
  final int rowCount;

  const AccountReference({
    required this.table,
    required this.column,
    required this.rowCount,
  });

  String get displayLabel {
    final labels = {
      'account_ledger_entries': 'قيود محاسبية',
      'treasury_transactions': 'معاملات خزينة',
      'bank_account_transactions': 'معاملات بنكية',
      'treasury_balances': 'أرصدة خزينة',
      'customers': 'عملاء',
      'suppliers': 'موردين',
      'clearing_agents': 'وكلاء تخليص',
      'shipping_companies': 'شركات شحن',
      'shareholders': 'مساهمين',
      'posting_profile_rules': 'قواعدOffsetTableprofiles',
      'cash_payments': 'مدفوعات نقدية',
      'transactions': 'معاملات',
      'treasuries': 'خزائن',
    };
    return labels[table] ?? table;
  }
}

class AccountActionResult {
  final bool success;
  final String action;
  final String? message;

  const AccountActionResult({
    required this.success,
    required this.action,
    this.message,
  });
}
