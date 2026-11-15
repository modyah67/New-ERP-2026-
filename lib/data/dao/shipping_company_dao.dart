import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipping_company_model.dart';

class ShippingCompanyDao {
  final _client = Supabase.instance.client;
  static const _table = 'shipping_companies';

  Future<String> generateNextCode() async {
    try {
      const minRange = 90000;
      const maxRange = 100000; // 90000 to 99999
      final response = await _client.from(_table).select('code');
      int maxCode = minRange - 1;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num = int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num >= minRange && num < maxRange && num > maxCode) maxCode = num;
      }
      if (maxCode < minRange) {
        return minRange.toString();
      }
      return (maxCode + 1).toString();
    } catch (e) {
      return '90000';
    }
  }

  /// Check if a shipping company code already exists in the database to prevent collisions
  Future<bool> checkCodeExists(String code, {int? excludeId}) async {
    try {
      final clean = code.trim();
      var query = _client.from(_table).select('id').eq('code', clean);
      if (excludeId != null) {
        query = query.neq('id', excludeId);
      }
      final res = await query.limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  ShippingCompanyModel _fromRow(Map<String, dynamic> row) {
    String? str(dynamic v) => v?.toString();
    double dbl(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    return ShippingCompanyModel(
      id: (row['id'] as num?)?.toInt(),
      code: str(row['code']) ?? '',
      name: str(row['name']) ?? '',
      phone: str(row['phone']) ?? '',
      email: str(row['email']) ?? '',
      balance: dbl(row['computed_balance'] ?? row['current_balance'] ?? row['balance']),
      initialBalance: dbl(row['initial_balance']),
      initialBalanceDirection: str(row['initial_balance_direction']) ?? 'CREDIT',
      currency: str(row['currency']) ?? 'EGP',
      createdAt: str(row['created_at']) ?? '',
    );
  }

  Future<List<ShippingCompanyModel>> getAll({int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from(_table)
        .select()
        .order('name')
        .range(offset, offset + limit - 1);

    Map<int, double>? trueBalances;
    try {
      final res = await _client.rpc('get_shipping_company_true_balances');
      if (res is List) {
        trueBalances = {};
        for (final r in res) {
          final id = (r['shipping_company_id'] as num?)?.toInt();
          if (id != null) {
            trueBalances[id] = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (e) {
      debugPrint('get_shipping_company_true_balances RPC error: $e');
    }

    return rows.map((row) {
      final id = (row['id'] as num?)?.toInt();
      if (trueBalances != null && id != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      }
      return _fromRow(row);
    }).toList();
  }

  Future<ShippingCompanyModel?> getById(int id) async {
    final data = await _client.from(_table).select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<List<ShippingCompanyModel>> search(String query, {int limit = 50, int offset = 0}) async {
    var builder = _client.from(_table).select();

    if (query.isNotEmpty) {
      builder = builder.or('name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%');
    }

    final rows = await builder.order('name').range(offset, offset + limit - 1);

    Map<int, double>? trueBalances;
    try {
      final res = await _client.rpc('get_shipping_company_true_balances');
      if (res is List) {
        trueBalances = {};
        for (final r in res) {
          final id = (r['shipping_company_id'] as num?)?.toInt();
          if (id != null) {
            trueBalances[id] = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (e) {
      debugPrint('get_shipping_company_true_balances RPC error: $e');
    }

    return rows.map((row) {
      final id = (row['id'] as num?)?.toInt();
      if (trueBalances != null && id != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      }
      return _fromRow(row);
    }).toList();
  }

  /// Resolves the master Level-5 summary account ID directly (21115: شركات الشحن)
  Future<int?> resolveMasterAccountId() async {
    try {
      final res = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', '21115')
          .limit(1)
          .maybeSingle();
      if (res != null && res['id'] != null) {
        return (res['id'] as num).toInt();
      }
      final fallback = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', '2111')
          .limit(1)
          .maybeSingle();
      return (fallback?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<int> insert(ShippingCompanyModel company) async {
    try {
      final insertMap = company.toInsertMap();
      if (!insertMap.containsKey('account_id') || insertMap['account_id'] == null) {
        final masterId = await resolveMasterAccountId();
        if (masterId != null) {
          insertMap['account_id'] = masterId;
        }
      }
      debugPrint('🟡 SHIPPING INSERT START');
      debugPrint('📦 DATA: $insertMap');

      final data = await _client
          .from(_table)
          .insert(insertMap)
          .select()
          .single();

      debugPrint('🟢 SHIPPING INSERT SUCCESS');
      debugPrint('📦 RETURNED: $data');

      final newId = (data['id'] as num).toInt();
      return newId;
    } catch (e, st) {
      debugPrint('🔴 SHIPPING INSERT ERROR');
      debugPrint('ERROR: $e');
      debugPrint('STACKTRACE: $st');
      rethrow;
    }
  }

  Future<void> update(ShippingCompanyModel company) async {
    final oldRow = await _client.from(_table).select('initial_balance, balance').eq('id', company.id!).single();
    final oldInitial = (oldRow['initial_balance'] as num?)?.toDouble() ?? 0.0;
    final oldBalance = (oldRow['balance'] as num?)?.toDouble() ?? 0.0;
    
    final diff = company.initialBalance - oldInitial;
    final newBalance = oldBalance + diff;

    await _client.from(_table).update({
      'code': company.code,
      'name': company.name,
      'phone': company.phone,
      'email': company.email,
      'balance': newBalance,
      'current_balance': newBalance,
      'initial_balance': company.initialBalance,
      'initial_balance_direction': company.initialBalanceDirection,
      'currency': company.currency,
    }).eq('id', company.id!);
  }

  Future<void> delete(int id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  Future<int> getCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }
}
