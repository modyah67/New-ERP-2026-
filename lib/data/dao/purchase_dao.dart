import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/purchase_model.dart';
import '../services/inventory_service.dart';

class PurchaseDao {
  final _client = Supabase.instance.client;

  /// Maps a raw row from purchase_invoices (+ embedded suppliers) into
  /// the column names that [PurchaseModel.fromMap] expects.
  PurchaseModel _mapPurchaseRow(dynamic e) {
    final row = Map<String, dynamic>.from(e as Map);
    final supplier = AppUtils.asMap(row.remove('suppliers'));
    return PurchaseModel.fromMap({
      'id': row['id'],
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
      'currency': row['currency'],
      'payment_treasury_id': row['payment_treasury_id'],
      'payment_source_type': row['payment_source_type'],
      'payment_bank_account_id': row['payment_bank_account_id'],
      'suppliers': supplier,
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
          .select('*, suppliers(name, code, currency)');

      if (fromDate != null) {
        query = query.gte('invoice_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('invoice_date', toDate);
      }

      if (productId != null) {
        final items = await _client
            .from('purchase_invoice_items')
            .select('invoice_id')
            .eq('raw_material_id', productId);
        final invoiceIds = items
            .map((e) => (e['invoice_id'] as num).toInt())
            .toSet()
            .toList();
        debugPrint(
            '📌 PurchaseDao.getAll: productId=$productId → ${invoiceIds.length} invoice(s)');
        if (invoiceIds.isEmpty) return [];
        query = query.inFilter('id', invoiceIds);
      }

      final data = await query
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);

      debugPrint('📌 PurchaseDao.getAll: returned ${data.length} rows');
      return data.map(_mapPurchaseRow).toList();
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.getAll error: $e\n$st');
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
            .or('name.ilike.$likePattern,code.ilike.$likePattern');
        supplierIds = supplierData
            .map((e) => (e['id'] as String))
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
          .select('*, suppliers(name, code, currency)')
          .or(orParts.join(','));

      if (fromDate != null) {
        query = query.gte('invoice_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('invoice_date', toDate);
      }

      if (productId != null) {
        final items = await _client
            .from('purchase_invoice_items')
            .select('invoice_id')
            .eq('raw_material_id', productId);
        final invoiceIds = items
            .map((e) => (e['invoice_id'] as num).toInt())
            .toSet()
            .toList();
        debugPrint(
            '📌 PurchaseDao.search: productId=$productId → ${invoiceIds.length} invoice(s)');
        if (invoiceIds.isEmpty) return [];
        query = query.inFilter('id', invoiceIds);
      }

      final data = await query
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);

      return data.map(_mapPurchaseRow).toList();
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.search error: $e\n$st');
      rethrow;
    }
  }

  Future<PurchaseModel?> getById(int id) async {
    try {
      final data = await _client
          .from('purchase_invoices')
          .select('*, suppliers(name, code, currency)')
          .eq('id', id.toString())
          .maybeSingle();

      if (data == null) return null;

      final purchase = _mapPurchaseRow(data);
      final items = await getItemsForPurchase(id);
      return purchase.copyWith(items: items);
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.getById error: $e\n$st');
      rethrow;
    }
  }

  Future<List<PurchaseItemModel>> getItemsForPurchase(int purchaseId) async {
    try {
      final data = await _client
          .from('purchase_invoice_items')
          .select()
          .eq('invoice_id', purchaseId.toString());

      final items = data.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        final rawStationId = row['station_id'];
        int? stationId = rawStationId is int
            ? rawStationId
            : int.tryParse(rawStationId?.toString() ?? '');
        double exchangeRate = (row['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        if (stationId == null || exchangeRate <= 1.0) {
          try {
            final snap = row['currency_snapshot'];
            if (snap is Map) {
              if (stationId == null && snap['station_id'] != null) {
                stationId = int.tryParse(snap['station_id'].toString());
              }
              if (exchangeRate <= 1.0 && snap['exchange_rate'] != null) {
                final snapRate = double.tryParse(snap['exchange_rate'].toString());
                if (snapRate != null && snapRate > 0) {
                  exchangeRate = snapRate;
                }
              }
            }
          } catch (_) {}
        }
        return PurchaseItemModel.fromMap({
          'id': row['id'],
          'purchase_id': row['invoice_id'],
          'item_id': row['raw_material_id'],
          'item_code': row['item_code'] ?? '',
          'item_name': row['item_name'] ?? '',
          'quantity': row['quantity'],
          'purchase_price': row['unit_cost'],
          'selling_price': 0,
          'total_price': row['total_cost'],
          'unit': row['unit'] ?? 'متر',
          'pieces_count': row['pieces_count'] ?? 0,
          'station_id': stationId,
          'exchange_rate': exchangeRate,
        });
      }).toList();

      for (int idx = 0; idx < items.length; idx++) {
        final item = items[idx];
        if (item.itemCode.isEmpty && item.itemId != null && item.itemId!.isNotEmpty) {
          try {
            final rm = await _client
                .from('raw_materials')
                .select('code, name, unit')
                .eq('id', item.itemId!)
                .maybeSingle();
            if (rm != null) {
              items[idx] = PurchaseItemModel(
                id: item.id, purchaseId: item.purchaseId, itemId: item.itemId,
                itemCode: rm['code'] ?? '', itemName: rm['name'] ?? '',
                quantity: item.quantity, purchasePrice: item.purchasePrice,
                sellingPrice: item.sellingPrice, totalPrice: item.totalPrice,
                unit: rm['unit'] ?? item.unit, piecesCount: item.piecesCount,
                stationId: item.stationId,
                exchangeRate: item.exchangeRate,
              );
            }
          } catch (_) {}
        }
      }

      final codes = items.map((i) => i.itemCode).where((c) => c.isNotEmpty).toList();
      if (codes.isNotEmpty) {
        try {
          final batches = await _client
              .from('station_product_batches')
              .select('station_id, product_code')
              .eq('source_type', 'purchase')
              .eq('source_id', purchaseId.toString())
              .inFilter('product_code', codes);

          final stationMap = <String, int>{};
          for (final b in batches) {
            final code = b['product_code']?.toString() ?? '';
            final sid = b['station_id'];
            if (code.isNotEmpty && sid != null && !stationMap.containsKey(code)) {
              stationMap[code] = sid is int ? sid : int.tryParse(sid.toString()) ?? 0;
            }
          }

          return items.map((i) {
            final stationId = i.stationId ?? stationMap[i.itemCode];
            return PurchaseItemModel(
              id: i.id, purchaseId: i.purchaseId, itemId: i.itemId,
              itemCode: i.itemCode, itemName: i.itemName,
              quantity: i.quantity, purchasePrice: i.purchasePrice,
              sellingPrice: i.sellingPrice, totalPrice: i.totalPrice,
              unit: i.unit, piecesCount: i.piecesCount, stationId: stationId,
              exchangeRate: i.exchangeRate,
            );
          }).toList();
        } catch (_) {}
      }

      return items;
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.getItemsForPurchase error: $e\n$st');
      rethrow;
    }
  }

  Future<int> insertWithItems(PurchaseModel purchase) async {
    try {
      final purchaseId = await _client.rpc('create_purchase', params: {
        'p_purchase_date': purchase.purchaseDate,
        'p_supplier_id': purchase.supplierId,
        'p_total_amount': purchase.totalAmount,
        'p_paid_amount': purchase.paidAmount,
        'p_discount_amount': purchase.discountAmount,
        'p_status': purchase.status,
        'p_notes': purchase.notes,
        'p_items': purchase.items
            .map((item) => {
                  'raw_material_id': item.itemId,
                  'quantity': item.quantity,
                  'unit_cost': item.purchasePrice,
                  'station_id': item.stationId,
                })
            .toList(),
      }) as int;

      try {
        final insertedItems = await _client
            .from('purchase_invoice_items')
            .select('id, raw_material_id')
            .eq('invoice_id', purchaseId.toString());

        for (final item in purchase.items) {
          if (item.stationId != null) {
            Map<String, dynamic>? row;
            for (final r in insertedItems) {
              if (r['raw_material_id'].toString() == item.itemId.toString()) {
                row = r;
                break;
              }
            }
            
            if (row != null) {
              await _client.from('purchase_invoice_items')
                  .update({'station_id': item.stationId})
                  .eq('id', row['id']);
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Could not persist station_id to DB after RPC: $e');
      }

      // ── INVENTORY WIRING ──────────────────────────────
      final inventoryService = InventoryService();
      for (final item in purchase.items) {
        try {
          await inventoryService.createBatchFromPurchase(
            productId: item.itemId.toString(),
            supplierId: purchase.supplierId,
            warehouseId: item.stationId?.toString(),
            purchaseInvoiceId: purchaseId.toString(),
            quantity: item.quantity.toDouble(),
            purchaseCost: item.purchasePrice.toDouble(),
          );
        } catch (e) {
          debugPrint('⚠️ Batch creation failed for product ${item.itemId}: $e');
        }
      }
      // ─────────────────────────────────────────────────

      return purchaseId;
    } catch (e) {
      debugPrint('⚠️ PurchaseDao.insertWithItems (RPC) error: $e');
      final purchaseData = await _client
          .from('purchase_invoices')
          .insert({
            ...purchase.toMap(),
            'supplier_id': purchase.supplierId,
            'user_id': _client.auth.currentUser?.id,
          })
          .select()
          .single();
      final purchaseId = purchaseData['id'] as int;
      if (purchase.items.isNotEmpty) {
        await _client.from('purchase_invoice_items').insert(
              purchase.items.map((item) {
        return {
          'invoice_id': purchaseId,
          'raw_material_id': item.itemId,
          'quantity': item.quantity,
          'unit_cost': item.purchasePrice,
          'station_id': item.stationId,
        };
              }).toList(),
            );
      }
      return purchaseId;
    }
  }

  Future<void> delete(int id) async {
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

      final result = (maxSeq + 1).toString().padLeft(6, '0');
      debugPrint('📌 getNextNumber: $result');
      return result;
    } catch (e) {
      debugPrint('⚠️ getNextNumber error: $e');
      return '000001';
    }
  }

  Future<void> confirmPurchase(String purchaseId) async {
    try {
      final id = int.tryParse(purchaseId);
      if (id == null) throw Exception('معرف المشتريات غير صالح');
      final result = await _client.rpc('rpc_confirm_purchase', params: {
        'p_purchase_id': id,
      });
      final map = Map<String, dynamic>.from(result as Map);
      if (map.containsKey('success') && map['success'] != true) {
        throw Exception(map['error']?.toString() ?? 'فشل تأكيد المشتريات');
      }
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.confirmPurchase error: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> cancelPurchase(String purchaseId) async {
    try {
      final id = int.tryParse(purchaseId);
      if (id == null) throw Exception('معرف المشتريات غير صالح');
      final result = await _client.rpc('rpc_cancel_purchase', params: {
        'p_purchase_id': id,
      });
      final map = Map<String, dynamic>.from(result as Map);
      if (map.containsKey('success') && map['success'] != true) {
        throw Exception(map['error']?.toString() ?? 'فشل إلغاء المشتريات');
      }
      return map;
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.cancelPurchase error: $e\n$st');
      rethrow;
    }
  }

  Future<double> editItemPrice({
    required String itemId,
    required String purchaseId,
    required double newPrice,
  }) async {
    try {
      final invoice = await _client
          .from('purchase_invoices')
          .select('status, total_amount')
          .eq('id', purchaseId)
          .maybeSingle();

      if (invoice == null) throw Exception('Invoice not found');

      final status = invoice['status'] as String?;
      
      if (status == 'draft') {
        final item = await _client
            .from('purchase_invoice_items')
            .select('quantity, unit_cost')
            .eq('id', itemId)
            .maybeSingle();
            
        if (item == null) throw Exception('Item not found');

        final quantity = (item['quantity'] as num).toDouble();
        final oldPrice = (item['unit_cost'] as num).toDouble();
        final delta = (newPrice - oldPrice) * quantity;
        
        await _client.from('purchase_invoice_items').update({
          'unit_cost': newPrice,
          'total_cost': newPrice * quantity,
        }).eq('id', itemId);

        final oldTotal = (invoice['total_amount'] as num).toDouble();
        await _client.from('purchase_invoices').update({
          'total_amount': oldTotal + delta,
        }).eq('id', purchaseId);

        return delta;
      }

      final result = await _client.rpc('rpc_edit_purchase_item_price', params: {
        'p_purchase_id': purchaseId,
        'p_item_id': itemId,
        'p_new_price': newPrice,
      });
      final map = Map<String, dynamic>.from(result as Map);
      if (map.containsKey('success') && map['success'] != true) {
        throw Exception(map['error']?.toString() ?? 'فشل تعديل السعر');
      }
      return (map['delta'] as num?)?.toDouble() ?? 0.0;
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.editItemPrice error: $e\n$st');
      rethrow;
    }
  }

  /// Fetches all journal entries related to a purchase (inventory, payment, price adjustments).
  /// Returns entries ordered newest-first.
  Future<List<Map<String, dynamic>>> getJournalEntriesForPurchase(String purchaseId) async {
    try {
      final data = await _client.rpc(
        'rpc_get_purchase_journal_entries',
        params: {'p_purchase_id': purchaseId},
      );
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      debugPrint('❌ PurchaseDao.getJournalEntriesForPurchase error: $e');
      return [];
    }
  }

  Future<List<PurchaseModel>> getBySupplier(
    String supplierId, {
    String? fromDate,
    String? toDate,
  }) async {
    try {
      debugPrint('📌 getBySupplier: supplierId=$supplierId fromDate=$fromDate toDate=$toDate');
      var query = _client
          .from('purchase_invoices')
          .select()
          .eq('supplier_id', supplierId);

      if (fromDate != null) {
        query = query.gte('invoice_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('invoice_date', toDate);
      }

      final data = await query.order('id', ascending: false).limit(1000);
      debugPrint('📌 getBySupplier: returned ${data.length} rows');

      final list = data.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        return PurchaseModel.fromMap({
          'id': row['id'],
          'purchase_number': row['invoice_number'],
          'purchase_date': row['invoice_date'],
          'supplier_id': row['supplier_id']?.toString(),
          'supplier_name': null,
          'supplier_code': null,
          'total_amount': row['total_amount'],
          'paid_amount': row['paid_amount'],
          'discount_amount': row['discount_amount'],
          'status': row['status'],
          'notes': row['notes'],
          'created_at': row['created_at'],
          'payment_treasury_id': row['payment_treasury_id'],
          'payment_source_type': row['payment_source_type'],
          'payment_bank_account_id': row['payment_bank_account_id'],
        });
      }).toList();

      // Also query crop purchase invoices (lot_receipts) for this supplier
      try {
        var lotQuery = _client
            .from('lot_receipts')
            .select()
            .eq('supplier_id', supplierId)
            .eq('is_confirmed', true);

        if (fromDate != null) {
          lotQuery = lotQuery.gte('receipt_date', fromDate);
        }
        if (toDate != null) {
          lotQuery = lotQuery.lte('receipt_date', toDate);
        }

        final lotData = await lotQuery.order('id', ascending: false).limit(1000);
        for (final item in lotData) {
          final lot = Map<String, dynamic>.from(item as Map);
          final totalCost = (lot['total_fruit_cost'] as num?)?.toDouble() ?? 0.0;
          final paidAmt = (lot['paid_amount'] as num?)?.toDouble() ?? 0.0;
          final lotNumber = lot['lot_number']?.toString() ?? '';
          final productName = lot['product_name']?.toString() ?? '';
          final displayName = productName.isNotEmpty ? '$lotNumber ($productName)' : lotNumber;

          list.add(PurchaseModel(
            id: 'lot_${lot['id']}',
            purchaseNumber: displayName,
            purchaseDate: lot['receipt_date']?.toString() ?? lot['created_at']?.toString() ?? '',
            supplierId: lot['supplier_id']?.toString(),
            totalAmount: totalCost,
            paidAmount: paidAmt,
            discountAmount: 0.0,
            status: paidAmt >= totalCost && totalCost > 0 ? 'paid' : (lot['status']?.toString() ?? 'received'),
            notes: 'crop_lot',
            currency: lot['currency']?.toString() ?? 'EGP',
            createdAt: lot['created_at']?.toString() ?? '',
            paymentTreasuryId: lot['payment_treasury_id']?.toString(),
            paymentSourceType: lot['payment_source_type']?.toString(),
            paymentBankAccountId: lot['payment_bank_account_id'] is int
                ? lot['payment_bank_account_id'] as int
                : int.tryParse(lot['payment_bank_account_id']?.toString() ?? ''),
            journalEntryId: lot['journal_entry_id']?.toString(),
          ));
        }
      } catch (e) {
        debugPrint('⚠️ PurchaseDao.getBySupplier lot_receipts fetch failed: $e');
      }

      return list;
    } catch (e, st) {
      debugPrint('❌ PurchaseDao.getBySupplier error: $e\n$st');
      rethrow;
    }
  }
}
