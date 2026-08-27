import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shareholder_model.dart';

class ShareholderDao {
  final _client = Supabase.instance.client;

  Future<String> generateNextCode() async {
    try {
      final response = await _client.from('shareholders').select('code');
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

  ShareholderModel _fromRow(Map<String, dynamic> row) {
    return ShareholderModel.fromMap(row);
  }

  Future<List<ShareholderModel>> getAll({int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from('v_shareholders')
        .select()
        .order('name')
        .range(offset, offset + limit - 1);

    return rows.map((row) => _fromRow(row)).toList();
  }

  Future<List<ShareholderModel>> search(String query, {int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from('v_shareholders')
        .select()
        .or('name.ilike.%$query%,code.ilike.%$query%')
        .order('name')
        .range(offset, offset + limit - 1);

    return rows.map((row) => _fromRow(row)).toList();
  }

  Future<ShareholderModel?> getByCode(String code) async {
    final row = await _client
        .from('v_shareholders')
        .select()
        .eq('code', code)
        .maybeSingle();
    if (row == null) return null;
    return _fromRow(row);
  }

  Future<void> insert(ShareholderModel shareholder) async {
    await _client.from('shareholders').insert(shareholder.toInsertMap());
  }

  Future<void> update(ShareholderModel shareholder) async {
    await _client
        .from('shareholders')
        .update(shareholder.toInsertMap())
        .eq('id', shareholder.id!);
  }

  Future<void> updateInitialBalance({
    required String id,
    required double egpBal,
    required String egpDir,
    required double usdBal,
    required String usdDir,
    required double eurBal,
    required String eurDir,
    required double gbpBal,
    required String gbpDir,
  }) async {
    await _client.rpc(
      'rpc_update_shareholder_all_balances',
      params: {
        'p_shareholder_id': id,
        'p_egp_bal': egpBal,
        'p_egp_dir': egpDir,
        'p_usd_bal': usdBal,
        'p_usd_dir': usdDir,
        'p_eur_bal': eurBal,
        'p_eur_dir': eurDir,
        'p_gbp_bal': gbpBal,
        'p_gbp_dir': gbpDir,
      },
    );
  }

  Future<void> delete(String code) async {
    await _client
        .from('shareholders')
        .delete()
        .eq('code', code);
  }

  Future<int> getCount() async {
    final response = await _client.from('shareholders').select().count(CountOption.exact);
    return response.count;
  }
}
