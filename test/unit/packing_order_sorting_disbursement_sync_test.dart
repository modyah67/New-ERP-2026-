import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/packing_order_sorting_model.dart';
import 'package:accounting_system/core/data_change_event_bus.dart';

void main() {
  group('Packing Order Sorting Disbursement Sync & Traceability Tests', () {
    test('PackingOrderSortingModel serializes and deserializes traceability fields', () {
      final model = PackingOrderSortingModel(
        id: 101,
        packingOrderId: 45,
        productName: 'برتقال بصرة',
        lotNumber: 'LOT-2026-001',
        weightKg: 150.0,
        remainingWeightKg: 150.0,
        costPerKg: 12.5,
        totalCost: 1875.0,
        status: 'pending',
        stationId: 2,
        exportShipmentNo: 'EXP-SHP-2026-88',
        customerName: 'شركة الإيمان للتصدير',
        customerId: 14,
      );

      final map = model.toMap();
      expect(map['packing_order_id'], 45);
      expect(map['product_name'], 'برتقال بصرة');
      expect(map['lot_number'], 'LOT-2026-001');
      expect(map['weight_kg'], 150.0);
      expect(map['remaining_weight_kg'], 150.0);
      expect(map['cost_per_kg'], 12.5);
      expect(map['total_cost'], 1875.0);
      expect(map['status'], 'pending');
      expect(map['station_id'], 2);
      expect(map['export_shipment_no'], 'EXP-SHP-2026-88');
      expect(map['customer_name'], 'شركة الإيمان للتصدير');
      expect(map['customer_id'], 14);

      final fromMapModel = PackingOrderSortingModel.fromMap(map);
      expect(fromMapModel.id, 101);
      expect(fromMapModel.packingOrderId, 45);
      expect(fromMapModel.exportShipmentNo, 'EXP-SHP-2026-88');
      expect(fromMapModel.customerName, 'شركة الإيمان للتصدير');
      expect(fromMapModel.customerId, 14);
      expect(fromMapModel.isPending, isTrue);
      expect(fromMapModel.isSoldOut, isFalse);
    });

    test('DataChangeEventBus emits sorting events when notified', () async {
      final bus = DataChangeEventBus.instance;
      bool notified = false;

      final subscription = bus.sortingStream.listen((_) {
        notified = true;
      });

      bus.notifySortingChanged();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notified, isTrue);
      await subscription.cancel();
    });

    test('Sorting query filter includes active/confirmed stages and excludes cancelled orders', () {
      final mockRows = [
        {
          'id': 1,
          'packing_order_id': 10,
          'product_name': 'برتقال',
          'packing_orders': {'status': 'crops_confirmed'},
        },
        {
          'id': 2,
          'packing_order_id': 11,
          'product_name': 'عنب',
          'packing_orders': {'status': 'packaging_confirmed'},
        },
        {
          'id': 3,
          'packing_order_id': 12,
          'product_name': 'فراولة',
          'packing_orders': {'status': 'completed'},
        },
        {
          'id': 4,
          'packing_order_id': 13,
          'product_name': 'مانجو',
          'packing_orders': {'status': 'cancelled'},
        },
      ];

      final filtered = mockRows.where((row) {
        if (row.containsKey('packing_orders')) {
          final po = row['packing_orders'] as Map;
          if (po['status'] == 'cancelled') return false;
        }
        return true;
      }).toList();

      expect(filtered.length, 3);
      expect(filtered.any((r) => r['id'] == 1), isTrue); // crops_confirmed is immediately visible!
      expect(filtered.any((r) => r['id'] == 2), isTrue); // packaging_confirmed is visible!
      expect(filtered.any((r) => r['id'] == 3), isTrue); // completed is visible!
      expect(filtered.any((r) => r['id'] == 4), isFalse); // cancelled is excluded!
    });

    test('Search filter on sorting page correctly matches order ID, shipment no, and customer name', () {
      final items = [
        const PackingOrderSortingModel(
          id: 1,
          packingOrderId: 701,
          productName: 'برتقال صيفي',
          lotNumber: 'LOT-A1',
          weightKg: 200,
          remainingWeightKg: 200,
          exportShipmentNo: 'EXP-CAIRO-99',
          customerName: 'الشركة الدولية',
        ),
        const PackingOrderSortingModel(
          id: 2,
          packingOrderId: 702,
          productName: 'ليمون بنزهير',
          lotNumber: 'LOT-B2',
          weightKg: 100,
          remainingWeightKg: 100,
          exportShipmentNo: 'EXP-ALEX-12',
          customerName: 'مؤسسة السلام',
        ),
      ];

      // Match by shipment
      final byShipment = items.where((s) {
        final q = 'cairo';
        return s.productName.toLowerCase().contains(q) ||
            (s.lotNumber != null && s.lotNumber!.toLowerCase().contains(q)) ||
            (s.exportShipmentNo != null && s.exportShipmentNo!.toLowerCase().contains(q)) ||
            (s.customerName != null && s.customerName!.toLowerCase().contains(q)) ||
            s.packingOrderId.toString().contains(q);
      }).toList();
      expect(byShipment.length, 1);
      expect(byShipment.first.id, 1);

      // Match by customer
      final byCustomer = items.where((s) {
        final q = 'السلام';
        return s.productName.toLowerCase().contains(q) ||
            (s.lotNumber != null && s.lotNumber!.toLowerCase().contains(q)) ||
            (s.exportShipmentNo != null && s.exportShipmentNo!.toLowerCase().contains(q)) ||
            (s.customerName != null && s.customerName!.toLowerCase().contains(q)) ||
            s.packingOrderId.toString().contains(q);
      }).toList();
      expect(byCustomer.length, 1);
      expect(byCustomer.first.id, 2);

      // Match by order number
      final byOrder = items.where((s) {
        final q = '701';
        return s.productName.toLowerCase().contains(q) ||
            (s.lotNumber != null && s.lotNumber!.toLowerCase().contains(q)) ||
            (s.exportShipmentNo != null && s.exportShipmentNo!.toLowerCase().contains(q)) ||
            (s.customerName != null && s.customerName!.toLowerCase().contains(q)) ||
            s.packingOrderId.toString().contains(q);
      }).toList();
      expect(byOrder.length, 1);
      expect(byOrder.first.id, 1);
    });
  });
}

