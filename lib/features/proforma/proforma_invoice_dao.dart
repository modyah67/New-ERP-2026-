import 'package:supabase_flutter/supabase_flutter.dart';
import 'proforma_invoice_model.dart';

class ProformaInvoiceDao {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ProformaInvoiceModel>> getAll({
    String? searchQuery,
    String? fromDate,
    String? toDate,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _client.from('proforma_invoices').select();
      if (fromDate != null) query = query.gte('invoice_date', fromDate);
      if (toDate != null) query = query.lte('invoice_date', toDate);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'invoice_no.ilike.%$searchQuery%,customer_name.ilike.%$searchQuery%,country.ilike.%$searchQuery%');
      }
      final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
      return data.map((row) => ProformaInvoiceModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getAll): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getAll): $e');
    }
  }

  Future<ProformaInvoiceModel?> getById(dynamic id) async {
    try {
      final data = await _client.from('proforma_invoices').select().eq('id', id.toString()).maybeSingle();
      if (data == null) return null;
      return ProformaInvoiceModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getById): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getById): $e');
    }
  }

  Future<List<ProformaInvoiceItem>> getItems(dynamic invoiceId) async {
    try {
      final data = await _client
          .from('proforma_invoice_items')
          .select()
          .eq('proforma_invoice_id', invoiceId.toString())
          .order('created_at');
      return data.map((row) => ProformaInvoiceItem.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getItems): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getItems): $e');
    }
  }

  Future<dynamic> insert(ProformaInvoiceModel invoice, {List<ProformaInvoiceItem> items = const []}) async {
    try {
      final data = invoice.toMap();
      data.remove('id');
      final result = await _client.from('proforma_invoices').insert(data).select().single();
      final invoiceId = result['id'];
      if (items.isNotEmpty) {
        final itemsData = items.map((item) {
          final m = item.toMap();
          m.remove('id');
          m['proforma_invoice_id'] = invoiceId;
          return m;
        }).toList();
        await _client.from('proforma_invoice_items').insert(itemsData);
      }
      return invoiceId;
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (insert): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (insert): $e');
    }
  }

  Future<void> update(ProformaInvoiceModel invoice, {List<ProformaInvoiceItem> items = const []}) async {
    try {
      final data = invoice.toMap();
      data.remove('id');
      data.remove('created_at');
      await _client.from('proforma_invoices').update(data).eq('id', invoice.id.toString());
      if (items.isNotEmpty) {
        await _client.from('proforma_invoice_items').delete().eq('proforma_invoice_id', invoice.id.toString());
        final itemsData = items.map((item) {
          final m = item.toMap();
          m.remove('id');
          m['proforma_invoice_id'] = invoice.id;
          return m;
        }).toList();
        await _client.from('proforma_invoice_items').insert(itemsData);
      }
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (update): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (update): $e');
    }
  }

  Future<void> delete(dynamic id) async {
    try {
      await _client.from('proforma_invoice_items').delete().eq('proforma_invoice_id', id.toString());
      await _client.from('proforma_invoices').delete().eq('id', id.toString());
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (delete): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (delete): $e');
    }
  }

  Future<String> getNextInvoiceNo(int year) async {
    try {
      final yy = (year % 100).toString().padLeft(2, '0');
      final prefix = 'PI/$yy/';
      final data = await _client
          .from('proforma_invoices')
          .select('invoice_no')
          .like('invoice_no', '$prefix%')
          .order('invoice_no', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return '${prefix}01';
      final last = (data['invoice_no'] ?? '').toString();
      final suffix = last.replaceFirst(prefix, '');
      final lastNum = int.tryParse(suffix) ?? 0;
      return '$prefix${(lastNum + 1).toString().padLeft(2, '0')}';
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getNextInvoiceNo): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getNextInvoiceNo): $e');
    }
  }
}
