import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/invoice_model.dart';
import '../services/inventory_service.dart';
import '../services/currency_conversion_service.dart';
import 'financial_audit_log_dao.dart';

class InvoiceDao {
  final _client = Supabase.instance.client;

  List<InvoiceModel> _flattenInvoices(List<dynamic> data) {
    return data.map((e) {
      final map = e is Map<String, dynamic> ? e : <String, dynamic>{};
      final flat = Map<String, dynamic>.from(map);
      final cust = AppUtils.asMap(flat['customers']);
      if (cust != null) {
        flat['customer_name'] = cust['name']?.toString();
        flat['customer_code'] = cust['code']?.toString();
      }
      flat.remove('customers');
      return InvoiceModel.fromMap(flat);
    }).toList();
  }

  InvoiceModel _flattenInvoice(Map<String, dynamic> data) {
    final flat = Map<String, dynamic>.from(data);
    final cust = AppUtils.asMap(flat['customers']);
    if (cust != null) {
      flat['customer_name'] = cust['name']?.toString();
      flat['customer_code'] = cust['code']?.toString();
    }
    flat.remove('customers');
    return InvoiceModel.fromMap(flat);
  }

  Future<List<InvoiceModel>> getAll({
    String? type,
    int limit = 50,
    int offset = 0,
    String? fromDate,
    String? toDate,
  }) async {
    var query = _client.from('invoices').select('*, customers(name, code)');
    if (type != null) query = query.eq('sale_type', type);
    if (fromDate != null) query = query.gte('invoice_date', fromDate);
    if (toDate != null) query = query.lte('invoice_date', toDate);
    final data = await query
        .order('invoice_number', ascending: false)
        .range(offset, offset + limit - 1);
    return _flattenInvoices(data);
  }

  Future<List<InvoiceModel>> getByCustomer(
    String customerId, {
    String? fromDate,
    String? toDate,
    String? type,
  }) async {
    var query = _client
        .from('invoices')
        .select('*, customers(name, code)')
        .eq('customer_id', customerId.toString());
    if (fromDate != null) query = query.gte('invoice_date', fromDate);
    if (toDate != null) query = query.lte('invoice_date', toDate);
    if (type != null) query = query.eq('sale_type', type);
    final data = await query.order('invoice_date').order('invoice_number').limit(1000);
    return _flattenInvoices(data);
  }

  Future<InvoiceModel?> getById(String id) async {
    final data = await _client
        .from('invoices')
        .select('*, customers(name, code)')
        .eq('id', id.toString())
        .maybeSingle();
    if (data == null) return null;
    final invoice = _flattenInvoice(data);
    final items = await getItemsForInvoice(id);
    return invoice.copyWith(items: items);
  }

  Future<List<InvoiceItemModel>> getItemsForInvoice(String invoiceId) async {
    final data = await _client
        .from('invoice_items')
        .select('*, finished_products(name, code)')
        .eq('invoice_id', invoiceId.toString());
    return data.map((map) {
      final flat = Map<String, dynamic>.from(map);
      final product = AppUtils.asMap(flat['finished_products']);
      if (product != null) {
        flat['item_name'] = product['name']?.toString();
        flat['item_code'] = product['code']?.toString();
      }
      flat.remove('finished_products');
      flat['item_id'] = flat['finished_product_id'];
      return InvoiceItemModel.fromMap(flat);
    }).toList();
  }

  Future<String> insertWithItems(InvoiceModel invoice) async {
    try {
      final invoiceId = await _client.rpc('create_invoice', params: {
        'p_invoice_date': invoice.invoiceDate,
        'p_customer_id': invoice.customerId,
        'p_total_amount': invoice.totalAmount,
        'p_paid_amount': invoice.paidAmount,
        'p_discount_amount': invoice.discountAmount,
        'p_status': invoice.status,
        'p_type': invoice.type,
        'p_notes': invoice.notes,
        'p_items': invoice.items
              .map((item) => {
                    'finished_product_id': item.itemId,
                    'quantity': item.quantity,
                    'unit_price': item.unitPrice,
                    'cost_price': item.costPrice,
                    'discount': 0,
                  })
            .toList(),
      }) as String;

      await _client.from('invoices').update({
        'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
          currency: 'EGP',
          amount: invoice.totalAmount,
          exchangeRate: 1.0,
        ).toJson(),
      }).eq('id', invoiceId);

      await FinancialAuditLogDao().logInsert(
        tableName: 'invoices',
        recordId: invoiceId,
        snapshot: {
          'customer_id': invoice.customerId,
          'total_amount': invoice.totalAmount,
          'paid_amount': invoice.paidAmount,
          'discount_amount': invoice.discountAmount,
          'status': invoice.status,
          'type': invoice.type,
          'items_count': invoice.items.length,
          'created_by': _client.auth.currentUser?.id,
        },
        reason: 'Invoice created via RPC',
      );

      // ── FIFO DEDUCTION ────────────────────────────────
      final inventoryService = InventoryService();
      for (final item in invoice.items) {
        try {
          await inventoryService.deductStockFIFO(
            productId: item.itemId ?? '',
            quantity: item.quantity.toDouble(),
            reason: 'sale',
            referenceId: invoiceId.toString(),
          );
        } catch (e) {
          debugPrint('⚠️ FIFO deduction failed for product ${item.itemId}: $e');
        }
      }
      // ─────────────────────────────────────────────────

      return invoiceId;
    } catch (e) {
      print('InvoiceDao error: $e');
      final invoiceData = await _client
          .from('sales_invoices')
          .insert({
            ...invoice.toMap(),
            'customer_id': invoice.customerId,
            'user_id': _client.auth.currentUser?.id,
            'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
              currency: 'EGP',
              amount: invoice.totalAmount,
              exchangeRate: 1.0,
            ).toJson(),
          }..remove('type'))
          .select()
          .single();
      final invoiceId = invoiceData['id'].toString();

      await FinancialAuditLogDao().logInsert(
        tableName: 'invoices',
        recordId: invoiceId,
        snapshot: {
          ...invoiceData,
          'items_count': invoice.items.length,
        },
        reason: 'Invoice created via fallback insert',
      );

      if (invoice.items.isNotEmpty) {
        await _client.from('sales_invoice_items').insert(
              invoice.items.map((item) {
                return {
                  'invoice_id': invoiceId,
                  'finished_product_id': item.itemId,
                  'quantity': item.quantity,
                  'unit_price': item.unitPrice,
                  'cost_price': item.costPrice,
                  'discount_amount': 0,
                  'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
                    currency: 'EGP',
                    amount: item.unitPrice * item.quantity.toDouble(),
                    exchangeRate: 1.0,
                  ).toJson(),
                };
              }).toList(),
            );
      }
      return invoiceId;
    }
  }

  Future<int> getNextNumber() async {
    try {
      final result = await _client.rpc('get_next_invoice_number');
      return int.tryParse(result.toString()) ?? 1;
    } catch (e) {
      print('InvoiceDao error: $e');
      return 1;
    }
  }

  Future<void> updateWithItems(InvoiceModel invoice) async {
    await _client
        .from('invoices')
        .update(invoice.toMap())
        .eq('id', invoice.id!.toString());
    await _client
        .from('invoice_items')
        .delete()
        .eq('invoice_id', invoice.id!.toString());
    if (invoice.items.isNotEmpty) {
      await _client.from('invoice_items').insert(
            invoice.items.map((item) {
              final map = item.toMap();
              map.remove('id');
              return map;
            }).toList(),
          );
    }
  }

  Future<void> update(InvoiceModel invoice) async {
    await _client
        .from('invoices')
        .update(invoice.toMap())
        .eq('id', invoice.id!.toString());
  }

  Future<void> delete(String id) async {
    try {
      await _client.rpc('delete_invoice', params: {'p_invoice_id': id});
    } catch (e) {
      print('InvoiceDao error: $e');
      await _client.from('invoice_items').delete().eq('invoice_id', id.toString());
      await _client.from('invoices').delete().eq('id', id.toString());
    }
  }

  Future<List<InvoiceModel>> search(
    String query, {
    String? type,
    String? fromDate,
    String? toDate,
    int limit = 50,
    int offset = 0,
  }) async {
    var filter = 'customers.name.ilike.%$query%';
    final invoiceNumber = int.tryParse(query);
    if (invoiceNumber != null) {
      filter = 'invoice_number.eq.$invoiceNumber,customers.name.ilike.%$query%';
    }
    var queryBuilder = _client
        .from('invoices')
        .select('*, customers(name, code)')
        .or(filter);
    if (type != null) queryBuilder = queryBuilder.eq('sale_type', type);
    if (fromDate != null) queryBuilder = queryBuilder.gte('invoice_date', fromDate);
    if (toDate != null) queryBuilder = queryBuilder.lte('invoice_date', toDate);
    final data = await queryBuilder
        .order('invoice_number', ascending: false)
        .range(offset, offset + limit - 1);
    return _flattenInvoices(data);
  }

  Future<int> getCount() async {
    final response = await _client.from('invoices').select().count(CountOption.exact);
    return response.count;
  }

  Future<double> getTotalRevenue() async {
    try {
      final result = await _client.rpc('get_total_revenue');
      if (result is num) return result.toDouble();
    } catch (_) {}
    final data = await _client.from('invoices').select('total_amount').limit(5000);
    return data.fold<double>(
      0.0,
      (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0.0),
    );
  }
}
