import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/proforma_invoice_model.dart';
import '../services/currency_conversion_service.dart';

class ProformaInvoiceDao {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ProformaInvoiceModel>> getAll({
    String? status,
    String? searchQuery,
    String? fromDate,
    String? toDate,
    int limit = 50,
    int offset = 0,
    String? excludeStatus,
  }) async {
    try {
      var query = _client.from('proforma_invoices').select();
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      } else if (excludeStatus != null && excludeStatus.isNotEmpty) {
        query = query.neq('status', excludeStatus);
      }
      if (fromDate != null) query = query.gte('shipment_date', fromDate);
      if (toDate != null) query = query.lte('shipment_date', toDate);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'shipment_no.ilike.%$searchQuery%,vessel_name.ilike.%$searchQuery%,container_number.ilike.%$searchQuery%');
      }
      final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
      return data.map((row) => ProformaInvoiceModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getAll): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getAll): $e');
    }
  }

  Future<ProformaInvoiceModel?> getLatest() async {
    try {
      final data = await _client
          .from('proforma_invoices')
          .select()
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return ProformaInvoiceModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getLatest): ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error (getLatest): $e');
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

  Future<dynamic> insert(ProformaInvoiceModel shipment) async {
    try {
      if (shipment.shipmentNo.trim().isEmpty) {
        throw Exception(' shipment_no cannot be empty');
      }
      final data = shipment.toMap();
      data.remove('id');
      // user_id is NOT sent — Supabase fills it via DEFAULT auth.uid()
      final result = await _client.from('proforma_invoices').insert(data).select().single();
      return result['id'];
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (insert): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (insert): $e');
    }
  }

  Future<void> update(ProformaInvoiceModel shipment) async {
    try {
      final data = shipment.toMap();
      data.remove('id');
      data.remove('created_at');
      await _client.from('proforma_invoices').update(data).eq('id', shipment.id.toString());
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (update): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (update): $e');
    }
  }

  Future<void> updatePackingRecipeId(dynamic shipmentId, String recipeId) async {
    try {
      await _client.from('proforma_invoices').update({'packing_recipe_id': recipeId}).eq('id', shipmentId.toString());
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updatePackingRecipeId): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updatePackingRecipeId): $e');
    }
  }

  Future<void> updateStatus(dynamic id, String status) async {
    try {
      await _client.from('proforma_invoices').update({'status': status}).eq('id', id.toString());
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updateStatus): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updateStatus): $e');
    }
  }

  Future<void> delete(dynamic id) async {
    try {
      final result = await _client
          .from('proforma_invoices')
          .delete()
          .eq('id', id.toString())
          .select() as List;
      print('ProformaInvoiceDao.delete: id=$id, rows_affected=${result.length}');
      if (result.isEmpty) {
        throw Exception('لم يتم العثور على الشحنة أو لا تملك صلاحية الحذف (id=$id)');
      }
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (delete): ${e.message} | code: ${e.code}');
    }
  }

  Future<void> syncLedger(dynamic shipmentId) async {
    try {
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid != null) {
        await _client.rpc('rpc_process_proforma_invoice_ledger', params: {
          'p_shipment_id': sid,
        });
      }
    } catch (e) {
      print('⚠️ Failed to sync ledger for shipment $shipmentId: $e');
    }
  }

  Future<String> getNextShipmentNo(String customerCode, int year) async {
    try {
      final yy = (year % 100).toString().padLeft(2, '0');
      final prefix = '$yy/$customerCode/';
      final data = await _client
          .from('proforma_invoices')
          .select('shipment_no')
          .like('shipment_no', '$prefix%')
          .order('shipment_no', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return '${prefix}01';
      final last = (data['shipment_no'] ?? '').toString();
      final suffix = last.replaceFirst(prefix, '');
      final lastNum = int.tryParse(suffix) ?? 0;
      final nextNum = lastNum + 1;
      return '$prefix${nextNum.toString().padLeft(2, '0')}';
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getNextShipmentNo): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getNextShipmentNo): $e');
    }
  }

  Future<List<ProformaInvoiceModel>> getByCustomer(dynamic customerId) async {
    try {
      final data = await _client
          .from('proforma_invoices')
          .select()
          .eq('customer_id', customerId.toString())
          .order('created_at', ascending: false);
      return data.map((row) => ProformaInvoiceModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getByCustomer): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getByCustomer): $e');
    }
  }

  Future<void> updateCosting({
    required int shipmentId,
    required double totalLandedCost,
    required int cartonCount,
    required double exportPricePerCarton,
    required String currencyCode,
    required double exchangeRate,
    double totalFruitCost = 0.0,
    double totalPackingMaterialCost = 0.0,
    double nonPackingLandedCost = 0.0,
  }) async {
    try {
      final costPerCarton = cartonCount > 0 ? totalLandedCost / cartonCount : 0.0;
      
      // Accurately calculate total revenue from items
      final itemsData = await _client.from('proforma_invoice_items').select('quantity, export_price_per_carton').eq('shipment_id', shipmentId.toString());
      double totalRevenueForeign = 0.0;
      for (final item in itemsData) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        final price = (item['export_price_per_carton'] as num?)?.toDouble() ?? 0;
        totalRevenueForeign += qty * price;
      }
      
      final totalRevenueEgp = CurrencyConversionService.instance.toBase(totalRevenueForeign, currencyCode, exchangeRate);
      
      // Fetch discount from existing shipment
      final shipmentData = await _client.from('proforma_invoices').select('discount_amount').eq('id', shipmentId.toString()).maybeSingle();
      final discount = (shipmentData?['discount_amount'] as num?)?.toDouble() ?? 0.0;
      
      final netProfit = totalRevenueEgp - totalLandedCost - discount;
      final grossProfit = totalRevenueEgp - totalFruitCost - totalPackingMaterialCost;

      await _client.from('proforma_invoices').update({
        'total_landed_cost': totalLandedCost,
        'cost_per_carton': costPerCarton,
        'export_price_per_carton': exportPricePerCarton,
        'currency_code': currencyCode,
        'exchange_rate': exchangeRate,
        'total_revenue_foreign': totalRevenueForeign,
        'total_revenue_egp': totalRevenueEgp,
        'net_profit_egp': netProfit,
        'total_fruit_cost': totalFruitCost,
        'total_packing_material_cost': totalPackingMaterialCost,
        'gross_profit': grossProfit,
        'net_profit': netProfit,
        'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
          currency: currencyCode,
          amount: totalRevenueForeign,
          exchangeRate: exchangeRate,
        ).toJson(),
      }).eq('id', shipmentId.toString());
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updateCosting): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updateCosting): $e');
    }
  }

  Future<Map<String, dynamic>> getProfitSummary() async {
    try {
      final data = await _client
        .from('proforma_invoices')
        .select('total_revenue_egp, total_landed_cost, net_profit_egp')
        .neq('status', 'cancelled');

      double totalRevenue = 0, totalCost = 0, totalProfit = 0;
      for (final row in data) {
        totalRevenue += (row['total_revenue_egp'] as num?)?.toDouble() ?? 0;
        totalCost += (row['total_landed_cost'] as num?)?.toDouble() ?? 0;
        totalProfit += (row['net_profit_egp'] as num?)?.toDouble() ?? 0;
      }
      return {
        'total_revenue_egp': totalRevenue,
        'total_cost_egp': totalCost,
        'net_profit_egp': totalProfit,
        'shipment_count': data.length,
      };
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getProfitSummary): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getProfitSummary): $e');
    }
  }

  Future<Map<String, double>> getItemTotals(List<dynamic> shipmentIds) async {
    if (shipmentIds.isEmpty) return {};
    try {
      final idStrs = shipmentIds.map((id) => id.toString()).toList();
      final data = await _client
          .from('proforma_invoice_items')
          .select('shipment_id, quantity, export_price_per_carton')
          .inFilter('shipment_id', idStrs);
      final totals = <String, double>{};
      for (final row in data) {
        final sid = row['shipment_id']?.toString() ?? '';
        final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
        final price = (row['export_price_per_carton'] as num?)?.toDouble() ?? 0;
        totals[sid] = (totals[sid] ?? 0) + qty * price;
      }
      return totals;
    } catch (e) {
      return {};
    }
  }
}
