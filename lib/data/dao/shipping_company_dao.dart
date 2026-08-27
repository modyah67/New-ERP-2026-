import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipping_company_model.dart';
import '../../core/services/tenant_service.dart';

class ShippingCompanyDao {
  final _client = Supabase.instance.client;
  static const _table = 'shipping_companies';

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

  ShippingCompanyModel _fromRow(Map<String, dynamic> row) {
    String? str(dynamic v) => v?.toString();
    double dbl(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    return ShippingCompanyModel(
      id: (row['id'] as num?)?.toInt(),
      code: str(row['code']) ?? '',
      name: str(row['name']) ?? '',
      phone: str(row['phone']) ?? '',
      email: str(row['email']) ?? '',
      balance: dbl(row['balance']),
      initialBalance: dbl(row['initial_balance']),
      initialBalanceDirection: str(row['initial_balance_direction']) ?? 'CREDIT',
      currency: str(row['currency']) ?? 'EGP',
      createdAt: str(row['created_at']) ?? '',
    );
  }

  Future<List<ShippingCompanyModel>> getAll({int limit = 50, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .order('name')
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
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

    final data = await builder.order('name').range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<int> insert(ShippingCompanyModel company) async {
    try {
      debugPrint('🟡 SHIPPING INSERT START');
      debugPrint('📦 DATA: ${company.toInsertMap()}');

      final data = await _client
          .from(_table)
          .insert(company.toInsertMap())
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
