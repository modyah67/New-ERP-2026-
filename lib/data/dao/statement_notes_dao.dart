import 'package:supabase_flutter/supabase_flutter.dart';

class StatementNotesDao {
  final _client = Supabase.instance.client;

  /// Load all notes for a given entity, keyed by reference_id
  Future<Map<String, String>> getNotes({
    required String entityType,
    required String entityId,
  }) async {
    final rows = await _client
        .from('statement_notes')
        .select('reference_id, note')
        .eq('entity_type', entityType)
        .eq('entity_id', entityId);

    final map = <String, String>{};
    for (final row in rows) {
      final refId = row['reference_id'].toString();
      final note = (row['note'] as String?) ?? '';
      if (note.isNotEmpty) {
        map[refId] = note;
      }
    }
    return map;
  }

  /// Upsert a single note (insert or update)
  Future<void> upsertNote({
    required String entityType,
    required String entityId,
    required String referenceId,
    required String note,
  }) async {
    await _client.from('statement_notes').upsert(
      {
        'entity_type': entityType,
        'entity_id': entityId,
        'reference_id': referenceId,
        'note': note,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'entity_type,entity_id,reference_id',
    );
  }

  /// Delete a single note
  Future<void> deleteNote({
    required String entityType,
    required String entityId,
    required String referenceId,
  }) async {
    await _client
        .from('statement_notes')
        .delete()
        .eq('entity_type', entityType)
        .eq('entity_id', entityId)
        .eq('reference_id', referenceId);
  }
}
