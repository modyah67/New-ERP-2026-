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

  Future<List<AccountModel>> getAll() async {
    final data = await _client
        .from('accounts')
        .select()
        .or('deleted_at.is.null')
        .order('account_code', ascending: true);
    final rawAccounts = (data as List).map((e) => AccountModel.fromMap(e)).toList();
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
    return (data as List).map((e) => AccountModel.fromMap(e)).toList();
  }
}
