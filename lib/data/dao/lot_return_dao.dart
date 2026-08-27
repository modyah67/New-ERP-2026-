import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';

class LotReturnModel {
  final String? id;
  final String lotReceiptId;
  final String? supplierId;
  final String? stationId;
  final double returnedQuantity;
  final double returnValue;
  final String? notes;
  final DateTime? createdAt;
  final String? createdBy;
  final int? journalEntryId;

  LotReturnModel({
    this.id,
    required this.lotReceiptId,
    this.supplierId,
    this.stationId,
    required this.returnedQuantity,
    required this.returnValue,
    this.notes,
    this.createdAt,
    this.createdBy,
    this.journalEntryId,
  });

  factory LotReturnModel.fromMap(Map<String, dynamic> map) {
    return LotReturnModel(
      id: map['id']?.toString(),
      lotReceiptId: map['lot_receipt_id'].toString(),
      supplierId: map['supplier_id']?.toString(),
      stationId: map['station_id']?.toString(),
      returnedQuantity: (map['returned_quantity'] as num?)?.toDouble() ?? 0.0,
      returnValue: (map['return_value'] as num?)?.toDouble() ?? 0.0,
      notes: map['notes']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      createdBy: map['created_by']?.toString(),
      journalEntryId: map['journal_entry_id'] as int?,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'lot_receipt_id': lotReceiptId,
      'supplier_id': supplierId,
      'station_id': stationId,
      'returned_quantity': returnedQuantity,
      'return_value': returnValue,
      'notes': notes,
    };
  }
}

class LotReturnDao {
  final _client = Supabase.instance.client;

  Future<List<LotReturnModel>> getAll({int limit = 50, int offset = 0}) async {
    final response = await _client
        .from('lot_returns')
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    
    return response.map((e) => LotReturnModel.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getHistoryWithDetails({int limit = 100}) async {
    final response = await _client
        .from('lot_returns')
        .select('''
          id,
          lot_receipt_id,
          supplier_id,
          station_id,
          returned_quantity,
          return_value,
          notes,
          created_at,
          created_by,
          journal_entry_id,
          lot_receipts (
            lot_number,
            product_name,
            purchase_mode,
            currency
          ),
          suppliers (
            name
          ),
          stations (
            name
          )
        ''')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> processReturn({
    required String lotId,
    required double returnQuantity,
    String? notes,
    String? stationId,
    int? batchId,
  }) async {
    final response = await _client
        .rpc('rpc_process_lot_return', params: {
          'p_lot_id': int.parse(lotId),
          'p_return_quantity': returnQuantity,
          if (notes != null && notes.isNotEmpty) 'p_notes': notes,
          if (stationId != null) 'p_station_id': int.parse(stationId),
          if (batchId != null) 'p_batch_id': batchId,
        })
        .timeout(const Duration(seconds: 30), onTimeout: () {
      throw Exception('انتهت مهلة الاتصال - حاول مرة أخرى');
    });

    final result = Map<String, dynamic>.from(response as Map);
    if (result['success'] != true) {
      throw Exception(result['error']?.toString() ?? 'فشل تسجيل المرتجع');
    }

    DataChangeEventBus.instance.notifyStationsChanged();
    DataChangeEventBus.instance.notifyItemsChanged();
    DataChangeEventBus.instance.notifyCropPurchasesChanged();
    DataChangeEventBus.instance.notifySuppliersChanged();

    return result;
  }
}
