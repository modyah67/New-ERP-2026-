import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stock_transfer_model.dart';

typedef WarehouseTransferDao = TransferDao;

class TransferDao {
  final _client = Supabase.instance.client;
  static const _table = 'stock_transfers';

  StockTransferModel _fromRow(Map<String, dynamic> row) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return StockTransferModel(
      id: intVal(row['id']),
      fromStationId: intVal(row['from_station_id']) ?? 0,
      toStationId: intVal(row['to_station_id']) ?? 0,
      productCode: str(row['product_code']) ?? '',
      productName: str(row['product_name']) ?? '',
      quantity: numVal(row['quantity'])?.toDouble() ?? 0.0,
      notes: str(row['notes']),
      transferredBy: str(row['transferred_by']) ?? '',
      createdAt: str(row['created_at']) ?? '',
      journalEntryId: intVal(row['journal_entry_id']),
      unitCost: numVal(row['unit_cost'])?.toDouble(),
      totalCost: numVal(row['total_cost'])?.toDouble(),
      currency: str(row['currency']) ?? 'EGP',
    );
  }

  Future<List<StockTransferModel>> getAll({int limit = 50, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<List<StockTransferModel>> getByStation(int stationId, {int limit = 50, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .or('from_station_id.eq.$stationId,to_station_id.eq.$stationId')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<List<StockTransferModel>> search(String query, {int limit = 50, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .or('product_name.ilike.%$query%,product_code.ilike.%$query%,notes.ilike.%$query%')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<int> insert(StockTransferModel transfer) async {
    final data = await _client
        .from(_table)
        .insert(transfer.toInsertMap())
        .select()
        .single();
    return (data['id'] as num).toInt();
  }

  Future<void> delete(int id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  Future<void> update(int id, Map<String, dynamic> data) async {
    await _client.from(_table).update(data).eq('id', id);
  }

  Future<StockTransferModel?> getById(int id) async {
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      return _fromRow(data);
    } catch (_) {
      return null;
    }
  }

  Future<int> getCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }

  Future<List<StockTransferModel>> getByDateRange(DateTime start, DateTime end, {int limit = 100, int offset = 0}) async {
    final data = await _client
        .from(_table)
        .select()
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String())
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  /// Automatically generates or links the balanced double-entry journal entry
  /// for a warehouse stock transfer.
  Future<int?> processTransferJournalEntry(int transferId) async {
    try {
      final res = await _client.rpc('rpc_process_stock_transfer_journal', params: {
        'p_transfer_id': transferId,
      });
      if (res is Map && res['success'] == true) {
        final jeId = res['journal_entry_id'];
        return jeId is int ? jeId : int.tryParse('$jeId');
      }
      debugPrint('TransferDao.processTransferJournalEntry warning: $res');
      return null;
    } catch (e, st) {
      debugPrint('TransferDao.processTransferJournalEntry error: $e\n$st');
      return null;
    }
  }

  /// Fetches the journal entry details for a stock transfer
  Future<Map<String, dynamic>?> getJournalEntryForTransfer(int transferId) async {
    try {
      final transfer = await getById(transferId);
      if (transfer?.journalEntryId != null) {
        final je = await _client
            .from('journal_entries')
            .select('id, entry_number, entry_date, description, source_type, source_id, created_at')
            .eq('id', transfer!.journalEntryId!)
            .maybeSingle();
        if (je != null) return Map<String, dynamic>.from(je);
      }

      final jeBySource = await _client
          .from('journal_entries')
          .select('id, entry_number, entry_date, description, source_type, source_id, created_at')
          .eq('source_type', 'stock_transfer')
          .eq('source_id', transferId.toString())
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (jeBySource != null) {
        if (transfer?.journalEntryId == null && jeBySource['id'] != null) {
          await update(transferId, {'journal_entry_id': jeBySource['id']});
        }
        return Map<String, dynamic>.from(jeBySource);
      }

      return null;
    } catch (e) {
      debugPrint('TransferDao.getJournalEntryForTransfer error: $e');
      return null;
    }
  }
}