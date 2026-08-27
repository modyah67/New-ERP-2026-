import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/packing_waste_model.dart';

class PackingWasteDao {
  final _client = Supabase.instance.client;

  Future<String> getNextWasteNumber() async {
    try {
      final rows = await _client
          .from('packing_wastes')
          .select('waste_number')
          .order('id', ascending: false)
          .limit(100);

      int maxSeq = 0;
      for (final row in rows) {
        final raw = '${row['waste_number'] ?? ''}'.trim();
        final matches = RegExp(r'\d+').allMatches(raw);
        if (matches.isNotEmpty) {
          final numVal = int.tryParse(matches.last.group(0)!) ?? 0;
          if (numVal > maxSeq && numVal < 100000) {
            maxSeq = numVal;
          }
        }
      }

      final nextNum = maxSeq + 1;
      return 'PW-$nextNum';
    } catch (e) {
      return 'PW-1';
    }
  }

  Future<List<PackingWasteModel>> getAll({int? stationId, String? status}) async {
    try {
      var query = _client.from('packing_wastes').select();
      if (stationId != null) query = query.eq('station_id', stationId);
      if (status != null) query = query.eq('status', status);
      final data = await query.order('created_at', ascending: false);
      return (data as List)
          .map((e) => PackingWasteModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint('❌ PackingWasteDao.getAll error: $e\n$st');
      rethrow;
    }
  }

  Future<PackingWasteModel?> getById(int id) async {
    try {
      final data = await _client.from('packing_wastes').select().eq('id', id).maybeSingle();
      if (data == null) return null;
      return PackingWasteModel.fromMap(Map<String, dynamic>.from(data));
    } catch (e, st) {
      debugPrint('❌ PackingWasteDao.getById error: $e\n$st');
      rethrow;
    }
  }

  Future<int> saveDraft(PackingWasteModel model) async {
    try {
      if (model.id != null) {
        await _client.from('packing_wastes').update(model.toMap()).eq('id', model.id!);
        return model.id!;
      } else {
        final res = await _client.from('packing_wastes').insert(model.toMap()).select('id').single();
        return res['id'] as int;
      }
    } catch (e, st) {
      debugPrint('❌ PackingWasteDao.saveDraft error: $e\n$st');
      rethrow;
    }
  }

  Future<String?> confirmWaste(int wasteId) async {
    try {
      final res = await _client.rpc('rpc_confirm_packing_waste', params: {'p_waste_id': wasteId});
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      if (map != null && map['success'] == true) {
        return null;
      }
      return map?['error']?.toString() ?? 'حدث خطأ غير متوقع أثناء تأكيد إذن الهالك';
    } catch (e, st) {
      debugPrint('❌ PackingWasteDao.confirmWaste error: $e\n$st');
      return e.toString();
    }
  }

  Future<void> deleteDraft(int wasteId) async {
    try {
      await _client.from('packing_wastes').delete().eq('id', wasteId).eq('status', 'draft');
    } catch (e, st) {
      debugPrint('❌ PackingWasteDao.deleteDraft error: $e\n$st');
      rethrow;
    }
  }
}
