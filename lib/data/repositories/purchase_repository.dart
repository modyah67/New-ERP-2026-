import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import 'package:uuid/uuid.dart';
import '../models/purchase_model.dart';

class PurchaseRepository {
  final _client = Supabase.instance.client;

  PurchaseModel _mapPurchaseRow(dynamic e) {
    final row = Map<String, dynamic>.from(e as Map);
    final supplier = AppUtils.asMap(row.remove('suppliers'));
    return PurchaseModel.fromMap({
      'id': row['id']?.toString(),
      'purchase_number': row['invoice_number'],
      'purchase_date': row['invoice_date'],
      'supplier_id': row['supplier_id']?.toString(),
      'supplier_name': supplier?['name'],
      'supplier_code': supplier?['code'],
      'total_amount': row['total_amount'],
      'paid_amount': row['paid_amount'],
      'discount_amount': row['discount_amount'],
      'status': row['status'],
      'notes': row['notes'],
      'created_at': row['created_at'],
    });
  }

  Future<List<PurchaseModel>> getAll({
    int limit = 50,
    int offset = 0,
    String? fromDate,
    String? toDate,
    String? productId,
  }) async {
    try {
      var query = _client
          .from('purchase_invoices')
          .select('*, suppliers(name, code)');

      if (fromDate != null) {
        query = query.gte('invoice_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('invoice_date', toDate);
      }

      if (productId != null && productId.isNotEmpty) {
        final items = await _client
            .from('purchase_invoice_items')
            .select('invoice_id')
            .eq('raw_material_id', productId.toString());
        final invoiceIds = items
            .map((e) => e['invoice_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        if (invoiceIds.isEmpty) return [];
        query = query.inFilter('id', invoiceIds);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return data.map(_mapPurchaseRow).toList();
    } catch (e, st) {
      debugPrint('❌ PurchaseRepository.getAll error: $e\n$st');
      rethrow;
    }
  }

  String _escapeForIlike(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  Future<List<PurchaseModel>> search(
    String searchQuery, {
    int limit = 50,
    int offset = 0,
    String? fromDate,
    String? toDate,
    String? productId,
  }) async {
    try {
      final trimmed = searchQuery.trim();
      if (trimmed.isEmpty) {
        return getAll(
          limit: limit,
          offset: offset,
          fromDate: fromDate,
          toDate: toDate,
          productId: productId,
        );
      }

      final escaped = _escapeForIlike(trimmed);
      final likePattern = '%$escaped%';

      List<String>? supplierIds;
      try {
        final supplierData = await _client
            .from('suppliers')
            .select('id')
            .ilike('name', likePattern);
        supplierIds = supplierData
            .map((e) => e['id']?.toString())
            .whereType<String>()
            .toList();
      } catch (e) {
        debugPrint('⚠️ Supplier search failed: $e');
      }

      final orParts = <String>[
        'invoice_number.ilike.$likePattern',
      ];
      if (supplierIds != null && supplierIds.isNotEmpty) {
        orParts.add('supplier_id.in.(${supplierIds.join(',')})');
      }

      var query = _client
          .from('purchase_invoices')
          .select('*, suppliers(name, code)')
          .or(orParts.join(','));

      if (fromDate != null) {
        query = query.gte('invoice_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('invoice_date', toDate);
      }

      if (productId != null && productId.isNotEmpty) {
        final items = await _client
            .from('purchase_invoice_items')
            .select('invoice_id')
            .eq('raw_material_id', productId.toString());
        final invoiceIds = items
            .map((e) => e['invoice_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        if (invoiceIds.isEmpty) return [];
        query = query.inFilter('id', invoiceIds);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return data.map(_mapPurchaseRow).toList();
    } catch (e, st) {
      debugPrint('❌ PurchaseRepository.search error: $e\n$st');
      rethrow;
    }
  }

  Future<PurchaseModel?> getById(String id) async {
    try {
      final data = await _client
          .from('purchase_invoices')
          .select('*, suppliers(name, code)')
          .eq('id', id.toString())
          .maybeSingle();

      if (data == null) return null;

      final purchase = _mapPurchaseRow(data);
      final items = await getItemsForPurchase(id);
      return purchase.copyWith(items: items, id: id);
    } catch (e, st) {
      debugPrint('❌ PurchaseRepository.getById error: $e\n$st');
      rethrow;
    }
  }

  Future<List<PurchaseItemModel>> getItemsForPurchase(String purchaseId) async {
    try {
      final data = await _client
          .from('purchase_invoice_items')
          .select('*, raw_materials(name, code)')
          .eq('invoice_id', purchaseId.toString());

      return data.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        final product = AppUtils.asMap(row['raw_materials']);
        return PurchaseItemModel.fromMap({
          'id': row['id']?.toString(),
          'purchase_id': row['invoice_id']?.toString(),
          'item_id': row['raw_material_id']?.toString(),
          'item_code': product?['code'] ?? '',
          'item_name': product?['name'] ?? '',
          'quantity': row['quantity'],
          'purchase_price': row['unit_cost'],
          'selling_price': 0.0,
          'total_price': row['total_cost'],
          'unit': 'كجم',
        });
      }).toList();
    } catch (e, st) {
      debugPrint('❌ PurchaseRepository.getItemsForPurchase error: $e\n$st');
      rethrow;
    }
  }

  Future<String> insertWithItems(PurchaseModel purchase) async {
    final purchaseId = await _client.rpc('create_purchase_workflow', params: {
      'p_purchase_date': purchase.purchaseDate,
      'p_supplier_id': purchase.supplierId,
      'p_total_amount': purchase.totalAmount,
      'p_paid_amount': purchase.paidAmount,
      'p_discount_amount': purchase.discountAmount,
      'p_status': purchase.status,
      'p_notes': purchase.notes,
      'p_idempotency_key': const Uuid().v4(),
      'p_items': purchase.items
          .map((item) => {
                'raw_material_id': item.itemId,
                'product_id': item.itemId,
                'quantity': item.quantity,
                'unit_cost': item.purchasePrice,
              })
          .toList(),
    });
    return purchaseId.toString();
  }

  Future<void> delete(String id) async {
    await _client.from('purchase_invoice_items').delete().eq('invoice_id', id.toString());
    await _client.from('purchase_invoices').delete().eq('id', id.toString());
  }

  Future<String> getNextNumber() async {
    try {
      final rows = await _client
          .from('purchase_invoices')
          .select('invoice_number')
          .order('id', ascending: false)
          .limit(100);

      int maxSeq = 0;
      for (final row in rows) {
        final raw = '${row['invoice_number'] ?? ''}'.trim();
        if (!RegExp(r'^\d+$').hasMatch(raw)) continue;
        final num = int.tryParse(raw) ?? 0;
        if (num > maxSeq) maxSeq = num;
      }

      return (maxSeq + 1).toString().padLeft(6, '0');
    } catch (e) {
      debugPrint('⚠️ getNextNumber error: $e');
      return '000001';
    }
  }

  Future<List<PurchaseModel>> getBySupplier(
    String supplierId, {
    String? fromDate,
    String? toDate,
  }) async {
    try {
      var query = _client
          .from('purchase_invoices')
          .select('*, suppliers(name, code)')
          .eq('supplier_id', supplierId);

      if (fromDate != null) {
        query = query.gte('invoice_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('invoice_date', toDate);
      }

      final data = await query.order('created_at', ascending: false);

      return data.map(_mapPurchaseRow).toList();
    } catch (e, st) {
      debugPrint('❌ PurchaseRepository.getBySupplier error: $e\n$st');
      rethrow;
    }
  }
}
