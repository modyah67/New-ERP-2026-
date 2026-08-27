import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/export_shipment_model.dart';

class ExportRepository {
  final SupabaseClient _client = Supabase.instance.client;
  static const _itemsTable = 'export_shipment_items';

  Future<List<ExportShipmentModel>> getAll({
    String? status,
    String? searchQuery,
    String? fromDate,
    String? toDate,
    int limit = 50,
    int offset = 0,
    String? excludeStatus,
  }) async {
    try {
      var query = _client.from('export_shipments').select();
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      } else if (excludeStatus != null && excludeStatus.isNotEmpty) {
        query = query.neq('status', excludeStatus);
      }
      if (fromDate != null) query = query.gte('shipment_date', fromDate);
      if (toDate != null) query = query.lte('shipment_date', toDate);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'shipment_number.ilike.%$searchQuery%,vessel_name.ilike.%$searchQuery%,container_number.ilike.%$searchQuery%');
      }
      final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
      return data.map((row) => ExportShipmentModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getAll): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getAll): $e');
    }
  }

  Future<ExportShipmentModel?> getById(String id) async {
    try {
      final data = await _client.from('export_shipments').select().eq('id', id).maybeSingle();
      if (data == null) return null;
      return ExportShipmentModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getById): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getById): $e');
    }
  }

  Future<String> insert(ExportShipmentModel shipment) async {
    try {
      final data = shipment.toMap();
      data.remove('id');
      final result = await _client.from('export_shipments').insert(data).select().single();
      return result['id'].toString();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (insert): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (insert): $e');
    }
  }

  Future<void> update(ExportShipmentModel shipment) async {
    try {
      final data = shipment.toMap();
      data.remove('id');
      data.remove('created_at');
      await _client.from('export_shipments').update(data).eq('id', shipment.id.toString());
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (update): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (update): $e');
    }
  }

  Future<void> updateStatus(String id, String status) async {
    try {
      await _client.from('export_shipments').update({'status': status}).eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updateStatus): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updateStatus): $e');
    }
  }

  Future<void> delete(String id) async {
    try {
      await deleteItemsByShipmentId(id);
      await _client.from('export_shipments').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (delete): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (delete): $e');
    }
  }

  // ── ExportShipmentItemDao Functionality ──

  Future<List<Map<String, dynamic>>> getItemsByShipmentId(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final data = await _client
        .from(_itemsTable)
        .select()
        .eq('shipment_id', parsedId);
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> deleteItemsByShipmentId(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    await _client
        .from(_itemsTable)
        .delete()
        .eq('shipment_id', parsedId);
  }

  Future<void> insertItems(String shipmentId, List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final rows = items
        .asMap()
        .entries
        .map((e) => {
              'shipment_id': parsedId,
              'finished_product_id': e.value['productId']?.toString(),
              'quantity': double.tryParse(e.value['qty']?.toString() ?? '0') ?? 0.0,
              'unit_price': double.tryParse(e.value['price']?.toString() ?? '0') ?? 0.0,
              'total_price': double.tryParse(e.value['amount']?.toString() ?? '0') ?? 0.0,
              'unit': e.value['unit']?.toString() ?? 'كجم',
              'carton_count': int.tryParse(e.value['cartonCount']?.toString() ?? '0') ?? 0,
              'net_weight': double.tryParse(e.value['netWt']?.toString() ?? '0') ?? 0.0,
              'gross_weight': double.tryParse(e.value['grossWt']?.toString() ?? '0') ?? 0.0,
            })
        .toList();

    await _client.from(_itemsTable).insert(rows);
  }
}
