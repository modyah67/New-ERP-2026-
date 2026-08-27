import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/invoice_model.dart';

class SalesRepository {
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
        .order('created_at', ascending: false)
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
        .eq('customer_id', customerId);
    if (fromDate != null) query = query.gte('invoice_date', fromDate);
    if (toDate != null) query = query.lte('invoice_date', toDate);
    if (type != null) query = query.eq('sale_type', type);
    final data = await query.order('created_at', ascending: false);
    return _flattenInvoices(data);
  }

  Future<InvoiceModel?> getById(String id) async {
    final data = await _client
        .from('invoices')
        .select('*, customers(name, code)')
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    final invoice = _flattenInvoice(data);
    final items = await getItemsForInvoice(id);
    return invoice.copyWith(items: items, id: id);
  }

  Future<List<InvoiceItemModel>> getItemsForInvoice(String invoiceId) async {
    final data = await _client
        .from('invoice_items')
        .select('*, finished_products(name, code)')
        .eq('invoice_id', invoiceId);
    return data.map((map) {
      final flat = Map<String, dynamic>.from(map);
      final product = AppUtils.asMap(flat['finished_products']);
      if (product != null) {
        flat['item_name'] = product['name']?.toString();
        flat['item_code'] = product['code']?.toString();
      }
      flat.remove('finished_products');
      flat['item_id'] = flat['finished_product_id']?.toString();
      return InvoiceItemModel.fromMap(flat);
    }).toList();
  }

  Future<String> insertWithItems(InvoiceModel invoice) async {
    try {
      final invoiceData = await _client
          .from('sales_invoices')
          .insert({
            ...invoice.toMap(),
            'customer_id': invoice.customerId,
            'user_id': _client.auth.currentUser?.id,
          })
          .select()
          .single();
      
      final invoiceId = invoiceData['id']?.toString() ?? '';
      
      if (invoice.items.isNotEmpty) {
        await _client.from('sales_invoice_items').insert(
          invoice.items.map((item) {
            return {
              'invoice_id': invoiceId,
              'finished_product_id': item.itemId,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'cost_price': item.costPrice,
              'total_price': item.totalPrice,
            };
          }).toList(),
        );
      }
      return invoiceId;
    } catch (e, st) {
      debugPrint('❌ SalesRepository.insertWithItems error: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _client.from('sales_invoice_items').delete().eq('invoice_id', id);
    await _client.from('sales_invoices').delete().eq('id', id);
  }

  Future<String> getNextNumber(String type) async {
    try {
      final today = DateTime.now();
      final typePrefix = type == 'export' ? 'EXP' : 'INV';
      final prefix =
          '$typePrefix-${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}-';

      final data = await _client
          .from('sales_invoices')
          .select('invoice_number')
          .like('invoice_number', '$prefix%')
          .order('invoice_number', ascending: false)
          .limit(1)
          .maybeSingle();

      int nextSeq = 1;
      if (data != null) {
        final raw = '${data['invoice_number']}';
        final match = RegExp(r'-(\d+)$').firstMatch(raw);
        if (match != null) {
          nextSeq = int.parse(match.group(1)!) + 1;
        }
      }

      final result = '$prefix${nextSeq.toString().padLeft(4, '0')}';
      return result;
    } catch (e) {
      debugPrint('⚠️ getNextNumber error: $e');
      return 'INV-${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
