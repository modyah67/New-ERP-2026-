import 'package:accounting_system/data/dao/packing_order_dao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackingOrderDao.buildAvailableForShipmentList', () {
    test('includes all final-approved variants with remaining stock regardless of customer', () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 1,
          'order_number': 'PO-001',
          'product_name': 'برتقال فالنسيا',
          'status': 'final_approved',
          'carton_count': 100,
          'sold_cartons': 25,
          'customer_name': 'عميل محدد',
          'export_shipment_no': 'SHP-99',
        },
        {
          'id': 2,
          'order_number': 'PO-002',
          'product_name': 'برتقال بصرة',
          'status': 'completed',
          'carton_count': 80,
          'sold_cartons': 0,
          'customer_name': null,
          'export_shipment_no': null,
        },
        {
          'id': 3,
          'order_number': 'PO-003',
          'product_name': 'يوسفي موركيت',
          'status': 'confirmed',
          'carton_count': 60,
          'sold_cartons': 10,
          'customer_name': '',
        },
        {
          'id': 4,
          'order_number': 'PO-004',
          'product_name': 'ليمون أضاليا',
          'status': 'costs_confirmed',
          'final_approved_at': '2026-10-01T10:00:00Z',
          'carton_count': 50,
          'sold_cartons': 0,
        },
      ];

      final available = PackingOrderDao.buildAvailableForShipmentList(rows);

      expect(available.map((e) => e.id).toList(), ['1', '2', '3', '4']);
      expect(available[0].remainingCartons, 75);
      expect(available[0].customerName, 'عميل محدد');
      expect(available[1].customerName, isNull);
    });

    test('excludes non-final-approved, cancelled, returned, and fully shipped orders', () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 10,
          'order_number': 'PO-DRAFT',
          'status': 'draft',
          'carton_count': 100,
          'sold_cartons': 0,
        },
        {
          'id': 11,
          'order_number': 'PO-PENDING',
          'status': 'pending',
          'carton_count': 100,
          'sold_cartons': 0,
        },
        {
          'id': 12,
          'order_number': 'PO-CROPS',
          'status': 'crops_confirmed',
          'carton_count': 100,
          'sold_cartons': 0,
        },
        {
          'id': 13,
          'order_number': 'PO-PKG',
          'status': 'packaging_confirmed',
          'carton_count': 100,
          'sold_cartons': 0,
        },
        {
          'id': 14,
          'order_number': 'PO-COSTS',
          'status': 'costs_confirmed',
          'carton_count': 100,
          'sold_cartons': 0,
        },
        {
          'id': 15,
          'order_number': 'PO-CANCELLED',
          'status': 'cancelled',
          'final_approved_at': '2026-10-01T10:00:00Z',
          'carton_count': 100,
          'sold_cartons': 0,
        },
        {
          'id': 16,
          'order_number': 'PO-RETURNED',
          'status': 'returned',
          'final_approved_at': '2026-10-01T10:00:00Z',
          'carton_count': 100,
          'sold_cartons': 0,
        },
        {
          'id': 17,
          'order_number': 'PO-SOLD-OUT',
          'status': 'final_approved',
          'carton_count': 100,
          'sold_cartons': 100,
        },
        {
          'id': 18,
          'order_number': 'PO-VALID',
          'status': 'final_approved',
          'carton_count': 100,
          'sold_cartons': 99,
        },
      ];

      final available = PackingOrderDao.buildAvailableForShipmentList(rows);

      expect(available.map((e) => e.id).toList(), ['18']);
      expect(available.single.remainingCartons, 1);
    });

    test('uses effective header/line counts for single-line orders so valid stock is never dropped', () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 20,
          'order_number': 'PO-020',
          'status': 'final_approved',
          'carton_count': 120,
          'sold_cartons': 20,
          'packing_cost_per_carton': 15.0,
        },
        {
          'id': 21,
          'order_number': 'PO-021',
          'status': 'final_approved',
          'carton_count': 50,
          'sold_cartons': 50,
        },
      ];
      final linesByOrderId = <int, List<Map<String, dynamic>>>{
        // Legacy/empty line count while header holds 120 cartons (20 sold)
        20: [
          {
            'id': 2001,
            'packing_order_id': 20,
            'product_name': 'رمان وندر فول',
            'carton_count': 0,
            'sold_cartons': 0,
            'final_cost': 1800.0,
          },
        ],
        // Line says 0 sold while header already marked all 50 cartons sold
        21: [
          {
            'id': 2002,
            'packing_order_id': 21,
            'product_name': 'عنب',
            'carton_count': 50,
            'sold_cartons': 0,
          },
        ],
      };

      final available = PackingOrderDao.buildAvailableForShipmentList(
        rows,
        linesByOrderId: linesByOrderId,
      );

      expect(available.length, 1);
      expect(available.single.id, '20');
      expect(available.single.lineId, 2001);
      expect(available.single.productName, 'رمان وندر فول');
      expect(available.single.cartonCount, 120);
      expect(available.single.soldCartons, 20);
      expect(available.single.remainingCartons, 100);
      expect(available.single.hasStock, isTrue);
      expect(available.single.packingCostPerCarton, 15.0);
    });

    test('expands multi-line final_approved order and filters selector options without customer constraints', () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 30,
          'order_number': 'PO-030',
          'status': 'final_approved',
          'customer_name': 'شركة النيل للتصدير',
          'export_shipment_no': 'EXP-30',
          'lot_receipts': {
            'lot_number': 'LOT-55',
            'suppliers': {'name': 'مزرعة الشمال'},
          },
        },
      ];
      final linesByOrderId = <int, List<Map<String, dynamic>>>{
        30: [
          {
            'id': 301,
            'packing_order_id': 30,
            'product_name': 'مانجو كيت',
            'carton_count': 40,
            'sold_cartons': 40, // depleted line -> excluded
          },
          {
            'id': 302,
            'packing_order_id': 30,
            'product_name': 'مانجو ناعومي',
            'carton_count': 60,
            'sold_cartons': 10,
            'final_cost': 1200.0,
          },
          {
            'id': 303,
            'packing_order_id': 30,
            'product_name': 'فراولة فريش',
            'carton_count': 30,
            'sold_cartons': 0,
          },
        ],
      };

      final built = PackingOrderDao.buildAvailableForShipmentList(
        rows,
        linesByOrderId: linesByOrderId,
      );

      expect(built.map((e) => e.lineId).toList(), [302, 303]);
      expect(built.first.lotNumber, 'LOT-55');
      expect(built.first.supplierName, 'مزرعة الشمال');

      // With empty search and one excluded line, remaining line still appears regardless of customer
      final afterSelectingOne = PackingOrderDao.filterAvailableOrdersForSelector(
        orders: built,
        excludedSelectionKeys: {'line_302'},
        pattern: '',
      );
      expect(afterSelectingOne.map((e) => e.lineId).toList(), [303]);

      // Search works by order number, lot number, product name, or customer name
      final byLot = PackingOrderDao.filterAvailableOrdersForSelector(
        orders: built,
        pattern: 'lot-55',
      );
      expect(byLot.length, 2);

      final byProduct = PackingOrderDao.filterAvailableOrdersForSelector(
        orders: built,
        pattern: 'فراولة',
      );
      expect(byProduct.map((e) => e.lineId).toList(), [303]);
    });
  });
}

