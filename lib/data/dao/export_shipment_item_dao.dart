import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/currency_conversion_service.dart';

class ExportShipmentItemDao {
  final _client = Supabase.instance.client;
  static const _table = 'export_shipment_items';

  Future<List<Map<String, dynamic>>> getByShipmentId(dynamic shipmentId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('shipment_id', shipmentId is int ? shipmentId : int.tryParse(shipmentId.toString()) ?? shipmentId)
        .order('sort_order');
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> deleteByShipmentId(dynamic shipmentId) async {
    final deleted = await _client
        .from(_table)
        .delete()
        .eq('shipment_id', shipmentId is int ? shipmentId : int.tryParse(shipmentId.toString()) ?? shipmentId)
        .select() as List;
    print('ExportShipmentItemDao.deleteByShipmentId: shipment_id=$shipmentId, rows_deleted=${deleted.length}');
  }

  Future<void> insertAll(
      dynamic shipmentId, List<Map<String, dynamic>> items, {
      String currencyCode = 'EGP',
      double exchangeRate = 1.0}) async {
    if (items.isEmpty) return;
    final rows = items
        .asMap()
        .entries
        .map((e) => {
              'shipment_id': shipmentId.toString(),
              'product_name': e.value['name'] ?? '',
              'invoice_product_name': e.value['product_name'] ?? '',
              'finished_product_id': e.value['productId'] == null
                  ? null
                  : int.tryParse(e.value['productId'].toString()),
              'grade': e.value['grade']?.toString(),
              'country_of_origin': e.value['countryOfOrigin']?.toString(),
              'hs_code': e.value['hsCode']?.toString(),
              'quantity': int.tryParse(e.value['qty']?.toString() ?? '0') ?? 0,
              'price':
                  double.tryParse(e.value['price']?.toString() ?? '0') ?? 0,
              'export_price_per_carton': double.tryParse(
                      e.value['exportPricePerCarton']?.toString() ?? '') ??
                  0,
              'weight_per_carton': double.tryParse(
                      e.value['weightPerCarton']?.toString() ?? '15') ??
                  15,
              'net_weight':
                  double.tryParse(e.value['netWt']?.toString() ?? '0') ?? 0,
              'gross_weight':
                  double.tryParse(e.value['grossWt']?.toString() ?? '0') ?? 0,
              'amount':
                  double.tryParse(e.value['amount']?.toString() ?? '0') ?? 0,
              'pallets':
                  int.tryParse(e.value['pallets']?.toString() ?? '0') ?? 0,
              'packing_order_id': e.value['packingOrderId'] == null
                  ? null
                  : int.tryParse(e.value['packingOrderId'].toString()),
              'packing_order_line_id': e.value['packing_order_line_id'] == null
                  ? null
                  : int.tryParse(e.value['packing_order_line_id'].toString()),
              'sort_order': e.key,
              'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
                currency: currencyCode,
                amount: double.tryParse(e.value['amount']?.toString() ?? '0') ?? 0,
                exchangeRate: exchangeRate,
              ).toJson(),
            })
        .toList();

    await _client.from(_table).insert(rows);
  }
}
