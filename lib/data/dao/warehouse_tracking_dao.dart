import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/warehouse_movement_model.dart';

class WarehouseTrackingDao {
  final _client = Supabase.instance.client;

  /// Fetch all movements (purchases, lots, packing, transfers) for a station
  Future<List<WarehouseMovementModel>> getMovementsForStation(
    String stationId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final allMovements = <WarehouseMovementModel>[];

    // Run all 4 independent sections in parallel
    final results = await Future.wait([
      _getPurchaseMovements(stationId, fromDate, toDate),
      _getLotMovements(stationId, fromDate, toDate),
      _getPackingMovements(stationId, fromDate, toDate),
      _getTransferMovements(stationId, fromDate, toDate),
      _getLotReturnMovements(stationId, fromDate, toDate),
    ]);

    for (final section in results) {
      allMovements.addAll(section);
    }

    // 5️⃣ Material transfers (depends on station name/products, runs after)
    try {
      allMovements.addAll(await _getMaterialTransfers(stationId, fromDate, toDate));
    } catch (e) {
      debugPrint('❌ WarehouseTrackingDao material transfers error: $e');
    }

    // Sort by createdAt descending (newest operation first)
    allMovements.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return b.date!.compareTo(a.date!);
      }
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      
      final cmp = b.createdAt!.compareTo(a.createdAt!);
      if (cmp != 0) return cmp;
      
      // If timestamps match exactly (e.g. Packing and its Materials)
      // put the main operation (packing) above materials
      if (a.type == MovementType.packing && b.type == MovementType.materialTransfer) return -1;
      if (a.type == MovementType.materialTransfer && b.type == MovementType.packing) return 1;
      
      // If timestamps match, Returns should logically be considered newer than Receipts/Transfers
      if (a.type == MovementType.lotReturn && (b.type == MovementType.lotReceipt || b.type == MovementType.transferIn || b.type == MovementType.transferOut)) return -1;
      if ((a.type == MovementType.lotReceipt || a.type == MovementType.transferIn || a.type == MovementType.transferOut) && b.type == MovementType.lotReturn) return 1;
      
      return 0;
    });

    return allMovements;
  }

  Future<List<WarehouseMovementModel>> _getPurchaseMovements(
      String stationId, DateTime? fromDate, DateTime? toDate) async {
    try {
      // Query purchase_invoices that have items assigned to this station (confirmed only)
      var purchaseQuery = _client
          .from('purchase_invoices')
          .select('*, suppliers(name), purchase_invoice_items!inner(station_id, quantity, unit_cost, raw_material_id, total_cost)')
          .eq('purchase_invoice_items.station_id', int.tryParse(stationId) ?? -1)
          .eq('status', 'confirmed');

      if (fromDate != null) {
        purchaseQuery = purchaseQuery.gte('invoice_date', AppUtils.formatDateForDb(fromDate));
      }
      if (toDate != null) {
        purchaseQuery = purchaseQuery.lte('invoice_date', AppUtils.formatDateForDb(toDate));
      }

      final purchases = await purchaseQuery.order('id', ascending: false);

      // Deduplicate (a purchase may have multiple items for the same station)
      final seen = <dynamic>{};
      final results = <WarehouseMovementModel>[];
      for (final p in purchases) {
        if (seen.contains(p['id'])) continue;
        seen.add(p['id']);

        final supplier = AppUtils.asMap(p['suppliers']);
        final items = p['purchase_invoice_items'] as List?;
        final totalQty = items?.fold<double>(0, (s, i) => s + ((i['quantity'] as num?)?.toDouble() ?? 0)) ?? 0;
        final totalCost = items?.fold<double>(0, (s, i) => s + ((i['total_cost'] as num?)?.toDouble() ?? 0)) ?? 0;

        results.add(WarehouseMovementModel(
          id: p['id'],
          type: MovementType.purchase,
          referenceNumber: p['invoice_number']?.toString() ?? '',
          date: _parseDate(p['invoice_date']),
          createdAt: _parseDateTime(p['created_at']?.toString()),
          productName: '${items?.length ?? 0} أصناف',
          quantity: totalQty,
          unit: 'قطعة',
          supplierName: supplier?['name']?.toString(),
          details: null,
        ));
      }
      return results;
    } catch (e) {
      debugPrint('❌ WarehouseTrackingDao purchases error: $e');
      return [];
    }
  }

  Future<List<WarehouseMovementModel>> _getLotMovements(
      String stationId, DateTime? fromDate, DateTime? toDate) async {
    try {
      var lotQuery = _client
          .from('lot_receipts')
          .select('*, suppliers(name)')
          .eq('station_id', stationId)
          .eq('is_confirmed', true);

      if (fromDate != null) {
        lotQuery = lotQuery.gte('receipt_date', AppUtils.formatDateForDb(fromDate));
      }
      if (toDate != null) {
        lotQuery = lotQuery.lte('receipt_date', AppUtils.formatDateForDb(toDate));
      }


      final lots = await lotQuery.order('id', ascending: false);

      return lots.map((l) {
        final supplier = AppUtils.asMap(l['suppliers']);
        final isCarton = l['purchase_mode'] == 'carton';
        return WarehouseMovementModel(
          id: l['id'],
          type: MovementType.lotReceipt,
          referenceNumber: 'لوت #${l['lot_number'] ?? l['id']}',
          date: _parseDate(l['receipt_date']),
          createdAt: _parseDateTime(l['created_at']?.toString()),
          productName: l['product_name']?.toString(),
          quantity: isCarton ? (l['carton_count'] as num?)?.toDouble() : (l['net_weight_kg'] as num?)?.toDouble(),
          unit: isCarton ? 'كرتونة' : 'كجم',
          supplierName: supplier?['name']?.toString(),
          details: isCarton 
              ? 'عدد الكراتين: ${l['carton_count'] ?? 0} كرتونة'
              : 'وزن خام: ${l['gross_weight_kg'] ?? 0} كجم | صافي: ${l['net_weight_kg'] ?? 0} كجم',
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ WarehouseTrackingDao lots error: $e');
      return [];
    }
  }

  Future<List<WarehouseMovementModel>> _getLotReturnMovements(
      String stationId, DateTime? fromDate, DateTime? toDate) async {
    try {
      var returnQuery = _client
          .from('lot_returns')
          .select('*, lot_receipts(lot_number, fruit_types(name)), suppliers(name)')
          .eq('station_id', stationId);

      if (fromDate != null) {
        returnQuery = returnQuery.gte('created_at', '${AppUtils.formatDateForDb(fromDate)}T00:00:00');
      }
      if (toDate != null) {
        returnQuery = returnQuery.lte('created_at', '${AppUtils.formatDateForDb(toDate)}T23:59:59');
      }

      final returns = await returnQuery.order('id', ascending: false);

      return returns.map((r) {
        final supplier = AppUtils.asMap(r['suppliers']);
        final lotReceipt = AppUtils.asMap(r['lot_receipts']);
        final fruitType = AppUtils.asMap(lotReceipt?['fruit_types']);
        final isCarton = lotReceipt?['purchase_mode'] == 'carton';
        
        return WarehouseMovementModel(
          id: r['id'],
          type: MovementType.lotReturn,
          referenceNumber: 'مرتجع لمحصول #${lotReceipt?['lot_number'] ?? r['lot_receipt_id']}',
          date: _parseDate(r['created_at']?.toString()),
          createdAt: _parseDateTime(r['created_at']?.toString()),
          productName: fruitType?['name']?.toString(),
          quantity: (r['returned_quantity'] as num?)?.toDouble(),
          unit: isCarton ? 'كرتونة' : 'كجم',
          supplierName: supplier?['name']?.toString(),
          details: r['notes']?.toString().isNotEmpty == true ? r['notes'].toString() : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ WarehouseTrackingDao lot returns error: $e');
      return [];
    }
  }

  Future<List<WarehouseMovementModel>> _getPackingMovements(
      String stationId, DateTime? fromDate, DateTime? toDate) async {
    try {
      var packingQuery = _client
          .from('packing_orders')
          .select('*, lot_receipts(lot_number, suppliers(name))')
          .eq('station_id', stationId)
          .inFilter('status', ['completed', 'cancelled']);

      if (fromDate != null) {
        packingQuery = packingQuery.gte('created_at', '${AppUtils.formatDateForDb(fromDate)}T00:00:00');
      }
      if (toDate != null) {
        packingQuery = packingQuery.lte('created_at', '${AppUtils.formatDateForDb(toDate)}T23:59:59');
      }

      final packings = await packingQuery.order('id', ascending: false);
      final movements = <WarehouseMovementModel>[];

      for (final pk in packings) {
        final lot = AppUtils.asMap(pk['lot_receipts']);
        final supplier = AppUtils.asMap(lot?['suppliers']);
        final isCarton = lot?['purchase_mode'] == 'carton';
        movements.add(WarehouseMovementModel(
          id: pk['id'],
          type: MovementType.packing,
          referenceNumber: 'تعبئة #${pk['order_number'] ?? pk['id']}',
          date: _parseDate(pk['packed_at']?.toString() ?? pk['created_at']?.toString()),
          createdAt: _parseDateTime(pk['created_at']?.toString()),
          productName: pk['product_name']?.toString(),
          quantity: isCarton ? (pk['carton_count'] as num?)?.toDouble() : (pk['total_net_weight'] as num?)?.toDouble(),
          unit: isCarton ? 'كرتونة' : 'كجم',
          supplierName: supplier?['name']?.toString() ?? pk['supplier_name']?.toString(),
          details: 'كراتين: ${pk['carton_count'] ?? 0} | درجة: ${pk['grade'] ?? ''}',
        ));

        // Extract packing materials from notes JSON
        try {
          final notesStr = pk['notes']?.toString();
          if (notesStr != null && notesStr.isNotEmpty) {
            final notesMap = jsonDecode(notesStr) as Map<String, dynamic>;
            final materials = notesMap['materials'] as List?;
            if (materials != null && materials.isNotEmpty) {
              for (int mi = 0; mi < materials.length; mi++) {
                final mat = materials[mi] as Map<String, dynamic>;
                final matName = mat['product_name']?.toString() ?? '';
                if (matName.isEmpty) continue;
                final usedQty = (mat['used_qty'] as num?)?.toDouble() ?? 0;
                final unitCost = (mat['unit_cost'] as num?)?.toDouble() ?? 0;
                final total = (mat['total'] as num?)?.toDouble() ?? 0;
                movements.add(WarehouseMovementModel(
                  id: pk['id'],
                  type: MovementType.materialTransfer,
                  referenceNumber: 'تعبئة #${pk['order_number'] ?? pk['id']}',
                  date: _parseDate(pk['packed_at']?.toString() ?? pk['created_at']?.toString()),
                  createdAt: _parseDateTime(pk['created_at']?.toString()),
                  productName: matName,
                  quantity: usedQty,
                  unit: 'قطعة',
                  details: 'استهلاك من تعبئة | سعر الوحدة: ${AppUtils.formatCurrency(unitCost)} | الإجمالي: ${AppUtils.formatCurrency(total)}',
                ));
              }
            }
          }
        } catch (_) {}
      }
      return movements;
    } catch (e) {
      debugPrint('❌ WarehouseTrackingDao packing error: $e');
      return [];
    }
  }

  Future<List<WarehouseMovementModel>> _getTransferMovements(
      String stationId, DateTime? fromDate, DateTime? toDate) async {
    try {
      var transferQuery = _client
          .from('stock_transfers')
          .select('*, from_station:stations!stock_transfers_from_station_id_fkey(name), to_station:stations!stock_transfers_to_station_id_fkey(name)')
          .or('from_station_id.eq.$stationId,to_station_id.eq.$stationId');

      if (fromDate != null) {
        transferQuery = transferQuery.gte('created_at', '${AppUtils.formatDateForDb(fromDate)}T00:00:00');
      }
      if (toDate != null) {
        transferQuery = transferQuery.lte('created_at', '${AppUtils.formatDateForDb(toDate)}T23:59:59');
      }

      final transfers = await transferQuery.order('id', ascending: false);

      return transfers.map((t) {
        final fromId = t['from_station_id'];
        final toId = t['to_station_id'];
        final isIncoming = toId?.toString() == stationId;
        final fromStation = AppUtils.asMap(t['from_station']);
        final toStation = AppUtils.asMap(t['to_station']);
        final fromName = fromStation?['name']?.toString() ?? fromId.toString();
        final toName = toStation?['name']?.toString() ?? toId.toString();
        return WarehouseMovementModel(
          id: t['id'],
          type: isIncoming ? MovementType.transferIn : MovementType.transferOut,
          referenceNumber: 'نقل #${t['id']}',
          date: _parseDate(t['created_at']?.toString()),
          createdAt: _parseDateTime(t['created_at']?.toString()),
          productName: t['product_name']?.toString(),
          quantity: (t['quantity'] as num?)?.toDouble(),
          details: isIncoming ? 'وارد من $fromName' : 'صادر إلى $toName',
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ WarehouseTrackingDao transfers error: $e');
      return [];
    }
  }

  Future<List<WarehouseMovementModel>> _getMaterialTransfers(
      String stationId, DateTime? fromDate, DateTime? toDate) async {
    final stationData = await _client
        .from('stations')
        .select('name')
        .eq('id', stationId)
        .maybeSingle();
    final stationName = stationData?['name']?.toString() ?? '';

    final stationProds = await _client
        .from('station_products')
        .select('product_name')
        .eq('station_id', stationId);
    final stationProductNames = stationProds
        .map((sp) => sp['product_name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    var movementQuery = _client
        .from('stock_movements')
        .select('id, description, movement_type, quantity, created_at')
        .or('movement_type.eq.transfer,movement_type.eq.return');

    if (fromDate != null) {
      movementQuery = movementQuery.gte('created_at', '${AppUtils.formatDateForDb(fromDate)}T00:00:00');
    }
    if (toDate != null) {
      movementQuery = movementQuery.lte('created_at', '${AppUtils.formatDateForDb(toDate)}T23:59:59');
    }

    final movements = await movementQuery.order('created_at', ascending: false);
    final results = <WarehouseMovementModel>[];

    for (final m in movements) {
      final desc = m['description']?.toString() ?? '';
      final productName = _extractProductNameFromDesc(desc);
      final isForStation = desc.contains('→ $stationName') ||
          (m['movement_type'] == 'return' &&
              stationProductNames.contains(productName));
      if (!isForStation) continue;

      final isIncoming = m['movement_type'] == 'transfer';
      results.add(WarehouseMovementModel(
        id: m['id'],
        type: MovementType.materialTransfer,
        referenceNumber: 'توريد مواد #${m['id']}',
        date: _parseDate(m['created_at']?.toString()),
        createdAt: _parseDateTime(m['created_at']?.toString()),
        productName: productName,
        quantity: (m['quantity'] as num?)?.toDouble(),
        unit: 'قطعة',
        details: isIncoming ? 'وارد من المخزن الرئيسي' : 'مرتجع إلى المخزن الرئيسي',
      ));
    }
    return results;
  }

  /// Get summary stats for ALL stations in one batch (avoids N+1)
  Future<Map<String, Map<String, int>>> getAllStationStats() async {
    final result = <String, Map<String, int>>{};

    // Run queries in parallel with per-query error handling
    final futures = await Future.wait([
      // 1. Purchases via purchase_invoice_items.station_id (confirmed only)
      _safeQuery(() => _client
          .from('purchase_invoice_items')
          .select('station_id, invoice_id, purchase_invoices!inner(status)')
          .eq('purchase_invoices.status', 'confirmed')),
      _safeQuery(() => _client.from('lot_receipts').select('station_id').eq('is_confirmed', true)),
      _safeQuery(() => _client.from('packing_orders').select('station_id').eq('status', 'completed')),
      _safeQuery(() => _client.from('stock_transfers')
          .select('from_station_id, to_station_id')),
      _safeQuery(() => _client.from('stations').select('id, name')),
      _safeQuery(() => _client.from('station_products').select('station_id, product_name')),
      _safeQuery(() => _client.from('stock_movements')
          .select('id, description, movement_type')
          .or('movement_type.eq.transfer,movement_type.eq.return')),
    ]);

    // 1. Process purchase items → count unique invoices per station
    Map<String, Set<dynamic>> purchaseCountsByStation = {};
    for (final b in futures[0]) {
      final sid = b['station_id']?.toString() ?? '';
      final pid = b['invoice_id'];
      if (sid.isNotEmpty) {
        purchaseCountsByStation.putIfAbsent(sid, () => {}).add(pid);
      }
    }

    // 2. Process lots
    Map<String, int> lotCounts = {};
    for (final l in futures[1]) {
      final sid = l['station_id']?.toString() ?? '';
      lotCounts[sid] = (lotCounts[sid] ?? 0) + 1;
    }

    // 3. Process packing
    Map<String, int> packingCounts = {};
    for (final p in futures[2]) {
      final sid = p['station_id']?.toString() ?? '';
      packingCounts[sid] = (packingCounts[sid] ?? 0) + 1;
    }

    // 4. Process transfers
    Map<String, int> transferCounts = {};
    for (final t in futures[3]) {
      final fromId = t['from_station_id']?.toString() ?? '';
      final toId = t['to_station_id']?.toString() ?? '';
      transferCounts[fromId] = (transferCounts[fromId] ?? 0) + 1;
      transferCounts[toId] = (transferCounts[toId] ?? 0) + 1;
    }

    // 5. Process station names + products + material transfers
    Map<String, String> stationNames = {};
    Map<String, List<String>> stationProductNames = {};
    for (final s in futures[4]) {
      stationNames[s['id']?.toString() ?? ''] = s['name']?.toString() ?? '';
    }

    for (final p in futures[5]) {
      final sid = p['station_id']?.toString() ?? '';
      final name = p['product_name']?.toString() ?? '';
      if (name.isNotEmpty) {
        stationProductNames.putIfAbsent(sid, () => []).add(name);
      }
    }

    // 6. Process material transfers using index lookup (O(N) instead of O(N*M))
    Map<String, int> materialCounts = {};
    final movements = futures[6];
    // Pre-index: for each movement, pre-compute productName + isIncoming candidates
    final List<(String desc, String productName, bool isReturn)> indexedMovements = [];
    for (final m in movements) {
      final desc = m['description']?.toString() ?? '';
      indexedMovements.add((desc, _extractProductNameFromDesc(desc), m['movement_type'] == 'return'));
    }
    for (final sid in stationNames.keys) {
      final sName = stationNames[sid] ?? '';
      final sProds = stationProductNames[sid] ?? [];
      int count = 0;
      for (final (desc, productName, isReturn) in indexedMovements) {
        if (desc.contains('→ $sName') || (isReturn && sProds.contains(productName))) {
          count++;
        }
      }
      materialCounts[sid] = count;
    }

    // Assemble all stats
    final allStationIds = <String>{
      ...purchaseCountsByStation.keys,
      ...lotCounts.keys,
      ...packingCounts.keys,
      ...transferCounts.keys,
      ...materialCounts.keys,
    };

    for (final sid in allStationIds) {
      result[sid] = {
        'purchases': purchaseCountsByStation[sid]?.length ?? 0,
        'lots': lotCounts[sid] ?? 0,
        'packing': packingCounts[sid] ?? 0,
        'transfers': transferCounts[sid] ?? 0,
        'materialTransfers': materialCounts[sid] ?? 0,
      };
    }

    return result;
  }

  /// Get summary stats for a single station (kept for detail page)
  Future<Map<String, int>> getStationStats(String stationId) async {
    int purchaseCount = 0;
    int lotCount = 0;
    int packingCount = 0;
    int transferCount = 0;
    int materialTransferCount = 0;

    try {
      final items = await _client
          .from('purchase_invoice_items')
          .select('invoice_id, purchase_invoices!inner(status)')
          .eq('station_id', int.tryParse(stationId) ?? -1)
          .eq('purchase_invoices.status', 'confirmed');
      purchaseCount = items.map((i) => i['invoice_id']).toSet().length;
    } catch (_) {}

    try {
      final lots = await _client
          .from('lot_receipts')
          .select('id')
          .eq('station_id', stationId);
      lotCount = lots.length;
    } catch (_) {}

    try {
      final packings = await _client
          .from('packing_orders')
          .select('id')
          .eq('station_id', stationId)
          .eq('status', 'completed');
      packingCount = packings.length;
    } catch (_) {}

    try {
      final transfers = await _client
          .from('stock_transfers')
          .select('id')
          .or('from_station_id.eq.$stationId,to_station_id.eq.$stationId');
      transferCount = transfers.length;
    } catch (_) {}

    try {
      final stationData = await _client
          .from('stations')
          .select('name')
          .eq('id', stationId)
          .maybeSingle();
      final stationName = stationData?['name']?.toString() ?? '';

      final stationProds = await _client
          .from('station_products')
          .select('product_name')
          .eq('station_id', stationId);
      final stationProductNames = stationProds
          .map((sp) => sp['product_name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final movements = await _client
          .from('stock_movements')
          .select('id, description, movement_type, quantity, created_at')
          .or('movement_type.eq.transfer,movement_type.eq.return');

      materialTransferCount = movements.where((m) {
        final desc = m['description']?.toString() ?? '';
        final productName = _extractProductNameFromDesc(desc);
        return desc.contains('→ $stationName') ||
            (m['movement_type'] == 'return' &&
                stationProductNames.contains(productName));
      }).length;
    } catch (_) {}

    return {
      'purchases': purchaseCount,
      'lots': lotCount,
      'packing': packingCount,
      'transfers': transferCount,
      'materialTransfers': materialTransferCount,
    };
  }

  /// Safe query wrapper: returns empty list on error instead of crashing
  Future<List<Map<String, dynamic>>> _safeQuery(
      Future<List<Map<String, dynamic>>> Function() query) async {
    try {
      return await query();
    } catch (e) {
      debugPrint('⚠️ WarehouseTrackingDao _safeQuery error: $e');
      return [];
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try { return DateTime.parse(value.toString()).toLocal(); } catch (_) { return null; }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    try { return DateTime.parse(value.toString()).toLocal(); } catch (_) { return null; }
  }

  String _extractProductNameFromDesc(String desc) {
    final match = RegExp(r'^(.+?)(?:\s*→|\s*←)').firstMatch(desc);
    return match?.group(1)?.trim() ?? desc;
  }

  Future<List<Map<String, dynamic>>> getStationProducts(String stationId) async {
    try {
      final data = await _client
          .from('station_products')
          .select('product_name, product_code, quantity, unit')
          .eq('station_id', stationId)
          .gt('quantity', 0)
          .order('product_name');
      return data.map((row) => {
        'product_name': row['product_name']?.toString() ?? '',
        'product_code': row['product_code']?.toString() ?? '',
        'quantity': (row['quantity'] as num?)?.toDouble() ?? 0.0,
        'unit': row['unit']?.toString() ?? 'kg',
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Batch fetch station products for ALL stations (1 query instead of N)
  Future<Map<String, List<Map<String, dynamic>>>> getAllStationProducts() async {
    try {
      final data = await _client
          .from('station_products')
          .select('station_id, product_name, product_code, quantity, unit')
          .gt('quantity', 0)
          .order('product_name');

      final result = <String, List<Map<String, dynamic>>>{};
      for (final row in data) {
        final sid = row['station_id']?.toString() ?? '';
        result.putIfAbsent(sid, () => []).add({
          'product_name': row['product_name']?.toString() ?? '',
          'product_code': row['product_code']?.toString() ?? '',
          'quantity': (row['quantity'] as num?)?.toDouble() ?? 0.0,
          'unit': row['unit']?.toString() ?? 'kg',
        });
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, Map<String, double>>> getAllStationValues() async {
    try {
      final data = await _client
          .from('station_product_batches')
          .select('station_id, remaining_quantity, unit_cost, currency');
      final result = <String, Map<String, double>>{};
      for (final row in data) {
        final sid = row['station_id']?.toString() ?? '';
        final remaining = (row['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (row['unit_cost'] as num?)?.toDouble() ?? 0.0;
        final currency = (row['currency'] as String?)?.toUpperCase() ?? 'EGP';
        result[sid] ??= {};
        result[sid]![currency] = (result[sid]![currency] ?? 0.0) + remaining * unitCost;
      }
      return result;
    } catch (_) {
      return {};
    }
  }
}
