import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/station_model.dart';

class StationDao {
  final _client = Supabase.instance.client;
  static const _table = 'stations';

  Future<String> generateNextCode() async {
    try {
      const minRange = 80000;
      const maxRange = 85000; // 80000 to 84999
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
      return '80000';
    }
  }

  /// Check if a station code already exists in the database to prevent collisions
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

  StationModel _fromRow(Map<String, dynamic> row) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');

    return StationModel(
      id: str(row['id']),
      code: str(row['code']) ?? '',
      name: str(row['name']) ?? '',
      description: str(row['description']),
      isActive: row['is_active'] == true || row['is_active'] == 1,
      type: str(row['type']) ?? 'sub',
      createdAt: str(row['created_at']) ?? '',
    );
  }

  Future<List<StationModel>> getAll({int limit = 50, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .order('name')
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<StationModel?> getMainStation() async {
    final data = await _client
        .from(_table)
        .select()
        .eq('type', 'main')
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<List<StationModel>> getSubStations({int limit = 100}) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('type', 'sub')
        .order('name')
        .limit(limit);
    return data.map(_fromRow).toList();
  }

  Future<List<StationModel>> search(String query, {int limit = 50, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .or('name.ilike.%$query%,code.ilike.%$query%')
        .order('name')
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<String> insert(StationModel station) async {
    final data = await _client
        .from(_table)
        .insert(station.toInsertMap())
        .select()
        .single();
    return data['id'].toString();
  }

  Future<void> update(StationModel station) async {
    await _client
        .from(_table)
        .update(station.toUpdateMap())
        .eq('id', station.id!);
  }

  Future<void> delete(String id) async {
    await _client.from('stock_transfers').delete().or('from_station_id.eq.$id,to_station_id.eq.$id');
    await _client.from(_table).delete().eq('id', id);
  }

  Future<StationModel?> getById(String id) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<int> getCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }
}
