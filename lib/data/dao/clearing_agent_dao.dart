import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clearing_agent_model.dart';

class ClearingAgentDao {
  final _client = Supabase.instance.client;

  static const _table = 'clearing_agents';

  Future<String> generateNextCode({String? brokerType}) async {
    try {
      final isSea = brokerType == null ||
          brokerType.trim().isEmpty ||
          brokerType.trim() == 'بحري' ||
          brokerType.trim().toLowerCase() == 'maritime' ||
          brokerType.trim().toLowerCase() == 'sea';

      final int minRange = isSea ? 20000 : 25000;
      final int maxRange = isSea ? 25000 : 30000;

      final response = await _client.from(_table).select('code');
      int maxCode = minRange - 1;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num = int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num >= minRange && num < maxRange && num > maxCode) {
          maxCode = num;
        }
      }
      if (maxCode < minRange) {
        return minRange.toString();
      }
      return (maxCode + 1).toString();
    } catch (e) {
      final isSea = brokerType == null || brokerType.trim() == 'بحري';
      return isSea ? '20000' : '25000';
    }
  }

  /// Check if a clearing agent code already exists in the database to prevent collisions
  Future<bool> checkCodeExists(String code, {String? excludeId}) async {
    try {
      final clean = code.trim();
      var query = _client.from(_table).select('id').eq('code', clean);
      if (excludeId != null && excludeId.isNotEmpty) {
        query = query.neq('id', excludeId);
      }
      final res = await query.limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _parseAddresses(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((a) {
      if (a is! Map) return <String, dynamic>{};
      final map = Map<String, dynamic>.from(a);
      if (map.containsKey('address') && !map.containsKey('address_line_1')) {
        map['address_line_1'] = map['address'];
      }
      if (map.containsKey('label') && !map.containsKey('type')) {
        map['type'] = map['label'].toString().contains('مختصر') ? 'quick' : 'full';
      }
      return map;
    }).toList();
  }

  ClearingAgentModel _fromRow(Map<String, dynamic> row) {
    String? str(dynamic v) => v?.toString();
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    final computedBal = row['computed_balance'] ?? row['current_balance'];
    final effectiveBal = computedBal != null
        ? (computedBal as num).toDouble()
        : (numVal(row['balance'])?.toDouble() ?? 0.0);

    return ClearingAgentModel(
      id: str(row['id']),
      code: str(row['code']) ?? '',
      name: str(row['name']) ?? '',
      phone: str(row['phone']) ?? '',
      city: str(row['city']) ?? '',
      country: str(row['country']) ?? '',
      gmail: str(row['gmail']) ?? '',
      brokerType: str(row['broker_type']) ?? 'بحري',
      contactPersonName: str(row['contact_person_name']) ?? '',
      contactPersonPhone: str(row['contact_person_phone']) ?? '',
      contactPersonEmail: str(row['contact_person_email']) ?? '',
      addresses: _parseAddresses(row['addresses']),
      balance: effectiveBal,
      initialBalance: numVal(row['initial_balance'])?.toDouble() ?? 0.0,
      initialBalanceDirection: str(row['initial_balance_direction']) ?? 'CREDIT',
      currency: str(row['currency']) ?? 'EGP',
      createdAt: str(row['created_at']) ?? '',
    );
  }

  Future<List<ClearingAgentModel>> getAll({int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from(_table)
        .select()
        .order('name')
        .range(offset, offset + limit - 1);

    Map<String, double>? trueBalances;
    try {
      final res = await _client.rpc('get_clearing_agent_true_balances');
      if (res is List) {
        trueBalances = {};
        for (final r in res) {
          final id = r['clearing_agent_id']?.toString();
          if (id != null) {
            trueBalances[id] = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (_) {}

    return rows.map((row) {
      final id = row['id']?.toString();
      if (trueBalances != null && id != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      }
      return _fromRow(row);
    }).toList();
  }

  Future<List<ClearingAgentModel>> search(String query, {String? typeFilter, int limit = 50, int offset = 0}) async {
    var queryBuilder = _client.from(_table).select();

    if (typeFilter != null && typeFilter.isNotEmpty) {
      queryBuilder = queryBuilder.eq('broker_type', typeFilter);
    }

    if (query.isNotEmpty) {
      queryBuilder = queryBuilder.or('name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%');
    }

    final rows = await queryBuilder
        .order('name')
        .range(offset, offset + limit - 1);

    Map<String, double>? trueBalances;
    try {
      final res = await _client.rpc('get_clearing_agent_true_balances');
      if (res is List) {
        trueBalances = {};
        for (final r in res) {
          final id = r['clearing_agent_id']?.toString();
          if (id != null) {
            trueBalances[id] = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (_) {}

    return rows.map((row) {
      final id = row['id']?.toString();
      if (trueBalances != null && id != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      }
      return _fromRow(row);
    }).toList();
  }

  /// Resolves the master Level-5 summary account ID directly (21116: مخلصي الجمارك)
  Future<int?> resolveMasterAccountId() async {
    try {
      final res = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', '21116')
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

  Future<String> insert(ClearingAgentModel agent) async {
    final agentData = agent.toInsertMap();
    if (agent.addresses.isNotEmpty) {
      agentData['addresses'] = agent.addresses;
    }

    if (!agentData.containsKey('account_id') || agentData['account_id'] == null) {
      final masterId = await resolveMasterAccountId();
      if (masterId != null) {
        agentData['account_id'] = masterId;
      }
    }

    final data = await _client
        .from(_table)
        .insert(agentData)
        .select()
        .single();

    final newId = data['id'].toString();
    return newId;
  }

  Future<void> update(ClearingAgentModel agent) async {
    final oldRow = await _client.from(_table).select('initial_balance, balance').eq('id', int.tryParse(agent.id!) ?? agent.id!).single();
    final oldInitial = (oldRow['initial_balance'] as num?)?.toDouble() ?? 0.0;
    final oldBalance = (oldRow['balance'] as num?)?.toDouble() ?? 0.0;
    
    final diff = agent.initialBalance - oldInitial;
    final newBalance = oldBalance + diff;

    await _client.from(_table).update({
      'code': agent.code,
      'name': agent.name,
      'phone': agent.phone,
      'city': agent.city,
      'country': agent.country,
      'gmail': agent.gmail,
      'broker_type': agent.brokerType,
      'contact_person_name': agent.contactPersonName,
      'contact_person_phone': agent.contactPersonPhone,
      'contact_person_email': agent.contactPersonEmail,
      'initial_balance': agent.initialBalance,
      'initial_balance_direction': agent.initialBalanceDirection,
      'balance': newBalance,
      'current_balance': newBalance,
      'currency': agent.currency,
      'addresses': agent.addresses,
    }).eq('id', int.tryParse(agent.id!) ?? agent.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', int.tryParse(id) ?? id);
  }

  Future<int> getCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }
}
