import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/account_model.dart';
import '../services/account_validation_service.dart';
import '../../core/extensions/company_injection.dart';
import '../../core/services/tenant_service.dart';

class AccountDao {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<AccountModel>> _hydrateLiveBalances(List<AccountModel> accounts) async {
    try {
      // Fetch per-account, per-currency net balances from account_ledger_entries
      final vLines = await _client
          .from('account_ledger_entries')
          .select('account_id, debit, credit, currency, amount_in_base_currency');

      // Per-currency: { accountId: { currency: net } }
      final Map<String, Map<String, double>> perCurrencySums = {};
      // Aggregated (EGP-equivalent) for unified official Chart of Accounts balance
      final Map<String, double> netSums = {};

      for (final line in (vLines as List)) {
        final accId = line['account_id']?.toString();
        if (accId == null || accId.isEmpty) continue;
        final debit = (line['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (line['credit'] as num?)?.toDouble() ?? 0.0;
        final currency = (line['currency']?.toString() ?? 'EGP').toUpperCase();
        final baseAmount = (line['amount_in_base_currency'] as num?)?.toDouble() ??
            (debit > 0 ? debit : credit);

        final net = debit - credit;
        final baseNet = debit > 0 ? baseAmount : (credit > 0 ? -baseAmount : 0.0);

        perCurrencySums.putIfAbsent(accId, () => {});
        perCurrencySums[accId]![currency] =
            (perCurrencySums[accId]![currency] ?? 0.0) + net;
        netSums[accId] = (netSums[accId] ?? 0.0) + baseNet;
      }

      if (netSums.isNotEmpty) {
        return accounts.map((acc) {
          if (acc.id != null && netSums.containsKey(acc.id)) {
            final net = netSums[acc.id]!;
            final typeLower = acc.type.toLowerCase();
            final liveBalance = (typeLower == 'liability' ||
                    typeLower == 'equity' ||
                    typeLower == 'revenue')
                ? -net
                : net;

            // Convert per-currency map with sign convention
            final currencyBalances = <String, double>{};
            final rawCurrencyMap = perCurrencySums[acc.id]!;
            for (final entry in rawCurrencyMap.entries) {
              final converted = (typeLower == 'liability' ||
                      typeLower == 'equity' ||
                      typeLower == 'revenue')
                  ? -entry.value
                  : entry.value;
              if (converted.abs() > 0.001) {
                currencyBalances[entry.key] = converted;
              }
            }

            return acc.copyWith(
              balance: liveBalance,
              balancesByCurrency: currencyBalances,
            );
          }
          return acc;
        }).toList();
      }
    } catch (_) {
      // Fallback to static balance in accounts table if view query fails
    }
    return accounts;
  }

  static const Set<String> _obsoleteLegacyCodes = {
    '112', '1121', '1112', '1113', '1114', '1115', '1116',
    '1213', '1214', '12122', '12123', '12124',
    '1222', '1223', '1224', '1225', '1232', '1233', '1234', '1235',
    '1242', '1243', '1244', '1245', '1246', '1247', '1248',
    '124101', '124102',
    '2123', '2124', '2125', '2126',
    '3121', '3123', '3212', '3222', '3223', '3224', '3412',
    '341', '3411',
  };

  Future<List<AccountModel>> getAll() async {
    final data = await _client
        .from('accounts')
        .select()
        .filter('deleted_at', 'is', null)
        .order('account_code', ascending: true);
    final rawAccounts = (data as List)
        .map((e) => AccountModel.fromMap(e))
        .where((acc) => !acc.isArchived && acc.isActive && !_obsoleteLegacyCodes.contains(acc.code.trim()))
        .toList();
    return _hydrateLiveBalances(rawAccounts);
  }

  /// Get all accounts including archived (for reports/historical views).
  Future<List<AccountModel>> getAllIncludingArchived() async {
    final data = await _client
        .from('accounts')
        .select()
        .order('account_code', ascending: true);
    final rawAccounts = (data as List).map((e) => AccountModel.fromMap(e)).toList();
    return _hydrateLiveBalances(rawAccounts);
  }

  /// Get only archived accounts.
  Future<List<AccountModel>> getArchived() async {
    final data = await _client
        .from('accounts')
        .select()
        .not('deleted_at', 'is', null)
        .order('account_code', ascending: true);
    return (data as List).map((e) => AccountModel.fromMap(e)).toList();
  }

  Future<AccountModel?> getById(String id) async {
    final data = await _client
        .from('accounts')
        .select()
        .eq('id', int.parse(id))
        .maybeSingle();
    if (data == null) return null;
    return AccountModel.fromMap(data);
  }

  Future<AccountModel?> getByCode(String code) async {
    final data = await _client
        .from('accounts')
        .select()
        .eq('account_code', code)
        .maybeSingle();
    if (data == null) return null;
    return AccountModel.fromMap(data);
  }

  Future<List<AccountModel>> getByCodes(List<String> codes) async {
    if (codes.isEmpty) return [];
    final data = await _client
        .from('accounts')
        .select()
        .inFilter('account_code', codes)
        .order('account_code', ascending: true);
    return (data as List).map((e) => AccountModel.fromMap(e)).toList();
  }

  Future<String> insert(AccountModel account) async {
    final data = await _client
        .from('accounts')
        .insert({...account.toMap(), 'created_by': _userId}.withCompanyId())
        .select('id')
        .single();
    return data['id'].toString();
  }

  Future<void> update(AccountModel account) async {
    await _client
        .from('accounts')
        .update(account.toMap())
        .eq('id', int.tryParse(account.id!) ?? account.id!)
        .eq('company_id', TenantService().tenantId!);
  }

  /// Safely update only the display names of an account without altering
  /// account_code, account_type, or parent_id, guaranteeing data integrity.
  Future<void> updateName({
    required String id,
    required String accountName,
    required String name,
  }) async {
    final updateData = {
      'account_name': accountName,
      'name': name,
    };
    var query = _client
        .from('accounts')
        .update(updateData)
        .eq('id', int.tryParse(id) ?? id);

    final tenantId = TenantService().tenantId;
    if (tenantId != null) {
      query = query.eq('company_id', tenantId);
    }
    await query;
  }

  /// Delete account using the generic validation engine.
  /// Returns [AccountActionResult] with details.
  Future<AccountActionResult> delete(String id) async {
    final validator = AccountValidationService();
    return validator.performAction('delete', id);
  }

  /// Archive account (soft delete).
  Future<AccountActionResult> archive(String id) async {
    final validator = AccountValidationService();
    return validator.archiveAccount(id);
  }

  /// Restore archived account.
  Future<AccountActionResult> restore(String id) async {
    final validator = AccountValidationService();
    return validator.restoreAccount(id);
  }

  /// Permanent delete (only for unused accounts).
  Future<AccountActionResult> permanentDelete(String id) async {
    final validator = AccountValidationService();
    return validator.permanentDeleteAccount(id);
  }

  /// Validate deletion without performing it.
  Future<AccountDeletionResult> validateDeletion(String id) async {
    final validator = AccountValidationService();
    return validator.validateDeletion(id);
  }

  /// Discover all FK references to an account.
  Future<List<AccountReference>> discoverReferences(String id) async {
    final validator = AccountValidationService();
    return validator.discoverReferences(id);
  }

  Future<bool> codeExists(String code, {String? excludeId}) async {
    var query = _client
        .from('accounts')
        .select('id')
        .eq('account_code', code);
    if (excludeId != null) {
      query = query.neq('id', int.parse(excludeId));
    }
    final data = await query.limit(1);
    return (data as List).isNotEmpty;
  }

  Future<bool> hasChildren(String parentId) async {
    final data = await _client
        .from('accounts')
        .select('id')
        .eq('parent_id', int.parse(parentId))
        .limit(1);
    return data.isNotEmpty;
  }

  Future<List<AccountModel>> search(String query) async {
    final data = await _client
        .from('accounts')
        .select()
        .or('deleted_at.is.null')
        .or('name.ilike.%$query%,account_name.ilike.%$query%,account_code.ilike.%$query%')
        .order('account_code', ascending: true);
    return (data as List)
        .map((e) => AccountModel.fromMap(e))
        .where((acc) => !acc.isArchived && acc.isActive && !_obsoleteLegacyCodes.contains(acc.code.trim()))
        .toList();
  }

  /// Search exclusively for posting accounts (Level 5 / Leaf accounts eligible for journal entries)
  Future<List<AccountModel>> searchPostingAccounts(String query) async {
    final all = await search(query);
    return all.where((acc) => acc.isLeaf && (acc.level == null || acc.level == 5)).toList();
  }

  /// Get next sequential sub-account code under parent account
  Future<String> getNextSubAccountCode(String parentCode) async {
    try {
      final res = await _client.rpc('get_next_sub_account_code', params: {
        'p_parent_code': parentCode,
        'p_company_id': TenantService().tenantId,
      });
      return res?.toString() ?? '${parentCode}1';
    } catch (_) {
      // Client-side fallback: query accounts starting with parentCode
      final accounts = await _client
          .from('accounts')
          .select('account_code')
          .like('account_code', '$parentCode%')
          .order('account_code', ascending: false)
          .limit(1);
      if ((accounts as List).isNotEmpty) {
        final lastCode = int.tryParse(accounts.first['account_code'].toString());
        if (lastCode != null) return (lastCode + 1).toString();
      }
      return '${parentCode}1';
    }
  }

  /// Create dynamic expense sub-account in Chart of Accounts
  Future<Map<String, dynamic>> createExpenseSubAccount({
    required String parentCode,
    required String nameAr,
    String? nameEn,
    String? costCenterId,
    String? customCode,
  }) async {
    try {
      final res = await _client.rpc('create_expense_sub_account', params: {
        'p_parent_code': parentCode,
        'p_name_ar': nameAr.trim(),
        if (nameEn != null && nameEn.trim().isNotEmpty) 'p_name_en': nameEn.trim(),
        if (costCenterId != null && costCenterId.isNotEmpty) 'p_cost_center_id': costCenterId,
        if (customCode != null && customCode.isNotEmpty) 'p_custom_code': customCode,
        'p_company_id': TenantService().tenantId,
      });
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      // Fallback: direct insert
      final code = customCode ?? await getNextSubAccountCode(parentCode);
      final parentData = await _client
          .from('accounts')
          .select('id, level')
          .eq('account_code', parentCode)
          .maybeSingle();

      final parentId = parentData?['id'];
      final parentLevel = parentData?['level'] as int? ?? 3;

      final insertData = {
        'account_code': code,
        'name': nameEn != null && nameEn.isNotEmpty ? nameEn.trim() : nameAr.trim(),
        'account_name': nameAr.trim(),
        'account_type': 'expense',
        'parent_id': parentId,
        'level': parentLevel + 1,
        'is_leaf': true,
        'allow_posting': true,
        'is_system': false,
        'is_active': true,
        'normal_balance': 'Debit',
        if (TenantService().tenantId != null) 'company_id': TenantService().tenantId,
      };

      final inserted = await _client
          .from('accounts')
          .insert(insertData)
          .select()
          .single();

      return {
        'success': true,
        'account_id': inserted['id'],
        'account_code': code,
        'name': inserted['name'],
        'account_name': inserted['account_name'],
        'cost_center_id': costCenterId,
      };
    }
  }
}
