import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clearing_agent_model.dart';
import '../../core/services/tenant_service.dart';

class ClearingAgentDao {
  final _client = Supabase.instance.client;

  static const _table = 'clearing_agents';
  Future<String> generateNextCode() async {
    try {
      final response = await _client.from(_table).select('code');
      int maxCode = 0;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num = int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num > maxCode) maxCode = num;
      }
      return (maxCode + 1).toString().padLeft(5, '0');
    } catch (e) {
      return '00001';
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
      balance: numVal(row['balance'])?.toDouble() ?? 0.0,
      initialBalance: numVal(row['initial_balance'])?.toDouble() ?? 0.0,
      currency: str(row['currency']) ?? 'EGP',
      createdAt: str(row['created_at']) ?? '',
    );
  }

  Future<List<ClearingAgentModel>> getAll({int limit = 50, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .order('name')
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<List<ClearingAgentModel>> search(String query, {String? typeFilter, int limit = 50, int offset = 0}) async {
    var queryBuilder = _client.from(_table).select();

    if (typeFilter != null && typeFilter.isNotEmpty) {
      queryBuilder = queryBuilder.eq('broker_type', typeFilter);
    }

    if (query.isNotEmpty) {
      queryBuilder = queryBuilder.or('name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%');
    }

    final data = await queryBuilder
        .order('name')
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<String> insert(ClearingAgentModel agent) async {
    final agentData = agent.toInsertMap();
    if (agent.addresses.isNotEmpty) {
      agentData['addresses'] = agent.addresses;
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
