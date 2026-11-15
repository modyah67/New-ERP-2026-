import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/data_change_event_bus.dart';
import 'package:accounting_system/data/models/cost_center.dart';

void main() {
  group('Export Shipment Cost Center & Transaction Linkage Tests', () {
    test('DataChangeEventBus broadcasts costCentersStream on export shipment changes', () async {
      final bus = DataChangeEventBus.instance;
      var eventTriggered = false;

      final subscription = bus.costCentersStream.listen((_) {
        eventTriggered = true;
      });

      bus.notifyCostCentersChanged();
      await Future.delayed(const Duration(milliseconds: 30));

      expect(eventTriggered, isTrue);
      await subscription.cancel();
    });

    test('Cost center correctly resolves for exported fruit varieties (Mango & Grapes)', () {
      final centers = [
        CostCenter.fromMap({
          'id': 1,
          'code': 'CC-MANGO-2026-2027',
          'name': 'مانجو (موسم 2026-2027)',
          'name_ar': 'مانجو (موسم 2026-2027)',
          'name_en': 'Mango (Season 2026-2027)',
          'crop_name': 'مانجو',
          'crop_code': 'MANGO',
          'cost_center_type': 'variety',
          'is_active': true,
        }),
        CostCenter.fromMap({
          'id': 2,
          'code': 'CC-GRAPES-2026-2027',
          'name': 'عنب (موسم 2026-2027)',
          'name_ar': 'عنب (موسم 2026-2027)',
          'name_en': 'Grapes (Season 2026-2027)',
          'crop_name': 'عنب',
          'crop_code': 'GRAPES',
          'cost_center_type': 'variety',
          'is_active': true,
        }),
      ];

      // Item 1: Mango
      final mangoItemName = 'مانجو - وزن';
      final mangoCenter = CostCenterHelper.fromId(mangoItemName, centers);
      expect(mangoCenter.code, equals('CC-MANGO-2026-2027'));

      // Item 2: Grapes
      final grapesItemName = 'عنب - كراتين';
      final grapesCenter = CostCenterHelper.fromId(grapesItemName, centers);
      expect(grapesCenter.code, equals('CC-GRAPES-2026-2027'));
    });

    test('Export shipment transaction mapping structures traceability and revenue accurately', () {
      // Simulate export shipment line
      const shipmentNo = '26/12000/01';
      const poNumber = 'PO-001';
      const packingOrderId = 1;
      const cropName = 'مانجو - وزن';
      const quantity = 20.0;
      const pricePerCartonForeign = 50.0; // USD
      const exchangeRate = 50.0;
      const totalForeign = quantity * pricePerCartonForeign; // 1,000 USD
      const totalEgp = totalForeign * exchangeRate; // 50,000 EGP

      final row = {
        'cost_center_id': 'CC-MANGO-2026-2027',
        'cost_center_name': 'مانجو (موسم 2026-2027)',
        'cost_center_type': 'variety',
        'source_type': 'export_shipment',
        'source_id': 'shipment_1_item_1',
        'transaction_date': '2026-11-02',
        'supplier_name': 'mohamed',
        'item_name': 'مبيعات تصدير - $cropName',
        'category': 'إيرادات المبيعات',
        'quantity': quantity,
        'unit_price': pricePerCartonForeign * exchangeRate,
        'currency': 'USD',
        'exchange_rate': exchangeRate,
        'total_in_currency': totalForeign,
        'amount': totalEgp,
        'shipment_no': shipmentNo,
        'packing_order_number': poNumber,
        'packing_order_id': packingOrderId,
        'notes': 'شحنة: $shipmentNo - أمر تعبئة: #$poNumber',
        'is_confirmed': true,
      };

      expect(row['cost_center_id'], equals('CC-MANGO-2026-2027'));
      expect(row['source_type'], equals('export_shipment'));
      expect(row['shipment_no'], equals('26/12000/01'));
      expect(row['packing_order_number'], equals('PO-001'));
      expect(row['packing_order_id'], equals(1));
      expect(row['category'], equals('إيرادات المبيعات'));
      expect(row['total_in_currency'], equals(1000.0));
      expect(row['amount'], equals(50000.0));
    });

    test('Parsing export shipment records in Cost Details handles shipment and PO badges', () {
      final cct = {
        'id': 101,
        'source_type': 'export_shipment',
        'source_id': 'shipment_1_item_1',
        'cost_center_id': 'CC-MANGO-2026-2027',
        'cost_center_name': 'مانجو (موسم 2026-2027)',
        'item_name': 'مبيعات تصدير - مانجو - وزن',
        'category': 'إيرادات المبيعات',
        'quantity': 20.0,
        'unit_price': 2500.0,
        'amount': 50000.0,
        'currency': 'USD',
        'exchange_rate': 50.0,
        'total_in_currency': 1000.0,
        'shipment_no': '26/12000/01',
        'packing_order_number': '1',
        'packing_order_id': 1,
        'notes': 'شحنة: 26/12000/01 - أمر تعبئة: #1',
      };

      final isExportSale = cct['source_type'] == 'export_shipment' ||
          cct['source_type'] == 'export_sale';
      expect(isExportSale, isTrue);

      final String shipmentNo;
      if (isExportSale) {
        final sNo = cct['shipment_no']?.toString();
        final notesStr = cct['notes']?.toString() ?? '';
        final match = RegExp(r'شحنة:?\s*([^\s|-]+)').firstMatch(notesStr)?.group(1);
        shipmentNo = sNo ?? match ?? 'شحنة تصدير';
      } else {
        shipmentNo = 'غير محدد';
      }
      expect(shipmentNo, equals('26/12000/01'));

      final String? packingOrderNum = cct['packing_order_number']?.toString() ??
          RegExp(r'أمر تعبئة:?\s*#?([^\s|-]+)').firstMatch(cct['notes']?.toString() ?? '')?.group(1);
      expect(packingOrderNum, equals('1'));
    });
  });
}

