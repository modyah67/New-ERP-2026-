import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves the GL account ID for a given treasury + currency combination.
///
/// Uses the `treasury_balances.account_id` column which maps each
/// treasury+currency balance to its corresponding chart of accounts entry.
///
/// Returns `null` if no mapping exists, allowing the caller to skip GL
/// entry creation gracefully.
class TreasuryAccountResolver {
  final _client = Supabase.instance.client;

  /// Returns the GL account ID (as int) for the given treasury + currency.
  ///
  /// Returns `null` if:
  /// - No `treasury_balances` row exists for this treasury+currency
  /// - The `account_id` column is NULL (e.g., employee treasury)
  /// - The account_id cannot be parsed as an integer
  Future<int?> getAccountId(String treasuryId, String currency) async {
    try {
      final data = await _client
          .from('treasury_balances')
          .select('account_id')
          .eq('treasury_id', treasuryId)
          .eq('currency', currency)
          .maybeSingle();

      if (data == null || data['account_id'] == null) {
        debugPrint(
          '⚠️ TreasuryAccountResolver: No GL account mapping for '
          'treasury=$treasuryId currency=$currency',
        );
        return null;
      }

      final raw = data['account_id'];
      if (raw is int) return raw;
      return int.tryParse('$raw');
    } catch (e) {
      debugPrint('⚠️ TreasuryAccountResolver: Error resolving account: $e');
      return null;
    }
  }
}
