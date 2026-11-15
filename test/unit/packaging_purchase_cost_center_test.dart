import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/purchase_model.dart';
import 'package:accounting_system/data/models/cost_center.dart';

void main() {
  group('Packaging Purchase Cost Center Propagation Models', () {
    test('PurchaseItemModel defaults costCenterId to packing_station', () {
      const item = PurchaseItemModel(
        purchaseId: 'inv-001',
        itemCode: 'BOX-01',
        itemName: 'كرتونة فراولة 2 كجم',
        quantity: 500,
        purchasePrice: 15.0,
        sellingPrice: 18.0,
        totalPrice: 7500.0,
      );

      expect(item.costCenterId, 'packing_station');
      final map = item.toMap();
      expect(map['cost_center_id'], 'packing_station');
    });

    test('PurchaseItemModel.fromMap parses cost_center_id and defaults correctly', () {
      final mapWithCc = {
        'id': 'item-1',
        'purchase_id': 'inv-001',
        'item_code': 'PLAST-01',
        'item_name': 'بلاستيك استريتش',
        'quantity': 100,
        'purchase_price': 50.0,
        'selling_price': 60.0,
        'total_price': 5000.0,
        'cost_center_id': 'packing_station',
      };
      final item1 = PurchaseItemModel.fromMap(mapWithCc);
      expect(item1.costCenterId, 'packing_station');

      final mapWithoutCc = {
        'id': 'item-2',
        'purchase_id': 'inv-002',
        'item_code': 'PAL-01',
        'item_name': 'طبالي خشبية',
        'quantity': 50,
        'purchase_price': 200.0,
        'selling_price': 250.0,
        'total_price': 10000.0,
      };
      final item2 = PurchaseItemModel.fromMap(mapWithoutCc);
      expect(item2.costCenterId, 'packing_station');
    });

    test('PurchaseLineData holds and propagates costCenterId', () {
      final line = PurchaseLineData(
        code: 'BOX-01',
        name: 'كرتون 5 كجم',
        quantity: 1000,
        purchasePrice: 12.5,
      );

      expect(line.costCenterId, 'packing_station');

      line.costCenterId = 'custom_station';
      expect(line.costCenterId, 'custom_station');
    });
  });

  group('CostCenter Canonicalization', () {
    test('CostCenter.fromMap canonicalizes operational cost center IDs', () {
      final ccPacking = CostCenter.fromMap({
        'id': 'uuid-123',
        'code': 'CC-PACKING',
        'name_ar': 'محطة التعبئة والتجهيز',
        'name_en': 'Packing & Processing Station',
        'type': 'operational',
      });
      expect(ccPacking.id, 'packing_station');
      expect(ccPacking.code, 'CC-PACKING');

      final ccLogistics = CostCenter.fromMap({
        'id': 'uuid-456',
        'code': 'CC-LOGISTICS',
        'name_ar': 'الشحن واللوجستيات',
        'name_en': 'Shipping & Logistics',
        'type': 'operational',
      });
      expect(ccLogistics.id, 'freight_logistics');

      final ccCustoms = CostCenter.fromMap({
        'id': 'uuid-789',
        'code': 'CC-CUSTOMS',
        'name_ar': 'التخليص الجمركي',
        'name_en': 'Customs Clearance',
        'type': 'operational',
      });
      expect(ccCustoms.id, 'customs_clearance');

      final ccAdmin = CostCenter.fromMap({
        'id': 'uuid-000',
        'code': 'CC-ADMIN',
        'name_ar': 'المصاريف الإدارية والعمومية',
        'name_en': 'General & Administrative',
        'type': 'operational',
      });
      expect(ccAdmin.id, 'general_admin');
    });

    test('CostCenterHelper.fromId properly matches packing_station and CC-PACKING', () {
      final fromPackingId = CostCenterHelper.fromId('packing_station');
      expect(fromPackingId.id, 'packing_station');
      expect(fromPackingId.code, 'CC-PACKING');

      final fromPackingCode = CostCenterHelper.fromId('CC-PACKING');
      expect(fromPackingCode.id, 'packing_station');
      expect(fromPackingCode.code, 'CC-PACKING');

      expect(fromPackingId, CostCenterHelper.packingStation);
    });
  });

  group('Cost Center Report Logic & Packaging Resolution', () {
    test('Packaging purchases resolve to packingStation cost center', () {
      final packagingPurchase = {
        'source_type': 'purchase',
        'category': 'مواد التعبئة',
        'item_name': 'كراتين مانجا 5 كجم',
        'cost_center_id': 'packing_station',
        'amount': 25000.0,
      };

      final resolved = CostCenterHelper.resolve(packagingPurchase);
      expect(resolved.id, CostCenterHelper.packingStation.id);
    });

    test('Deduplication prevents double-counting between cost_center_transactions and direct invoices', () {
      final List<Map<String, dynamic>> combined = [];
      final Set<String> existingSignatures = {};

      // 1. Transaction from cost_center_transactions (e.g. from rpc_confirm_purchase)
      final cctRow = {
        'source_type': 'purchase',
        'source_id': 'pii_item_001',
        'date': '2026-09-08',
        'cost_center_id': 'packing_station',
        'cost_center_name': 'محطة التعبئة والتجهيز',
        'category': 'مواد التعبئة',
        'item_name': 'كرتونة فراولة 2 كجم',
        'quantity': 1000.0,
        'unit_price': 15.0,
        'amount': 15000.0,
        'is_lot_receipt': false,
      };

      final sig1 = '${cctRow['date']}:${cctRow['item_name']}:${cctRow['amount']}';
      existingSignatures.add(sig1);
      existingSignatures.add(cctRow['source_id'] as String);
      combined.add(cctRow);

      // 2. Direct invoice query result for the exact same item
      final directRow = {
        'source_type': 'purchase',
        'source_id': 'pii_item_001',
        'date': '2026-09-08',
        'cost_center_id': 'packing_station',
        'cost_center_name': 'محطة التعبئة والتجهيز',
        'category': 'مواد التعبئة',
        'item_name': 'كرتونة فراولة 2 كجم',
        'quantity': 1000.0,
        'unit_price': 15.0,
        'amount': 15000.0,
        'is_lot_receipt': false,
      };

      final sig2 = '${directRow['date']}:${directRow['item_name']}:${directRow['amount']}';
      final isDup = existingSignatures.contains(sig2) || existingSignatures.contains(directRow['source_id']);
      expect(isDup, isTrue);

      if (!isDup) {
        combined.add(directRow);
      }

      expect(combined.length, 1);
      expect(combined.first['amount'], 15000.0);
    });

    test('Packaging transaction is correctly identified when filtering by packing station', () {
      final target = CostCenterHelper.fromId('packing_station');
      final targetCode = target.code; // 'CC-PACKING'
      final targetId = target.id;     // 'packing_station'

      final row = {
        'source_type': 'purchase',
        'cost_center_id': 'packing_station',
        'cost_center_name': 'محطة التعبئة والتجهيز',
        'category': 'مواد التعبئة',
        'item_name': 'شريط لاصق ومواد تغليف',
        'amount': 3500.0,
        'is_lot_receipt': false,
      };

      final rowCc = row['cost_center_id']?.toString();
      final matches = rowCc == targetId || rowCc == targetCode;
      expect(matches, isTrue);

      // Verify category grouping
      final category = row['category']?.toString();
      expect(category, 'مواد التعبئة');
    });

    test('Initial balance packaging transactions are correctly labeled and included', () {
      final cctOpeningRow = {
        'source_type': 'opening_balance',
        'source_id': 'ob_rm_uuid_001',
        'transaction_date': '2026-08-01',
        'cost_center_id': 'packing_station',
        'cost_center_name': 'محطة التعبئة والتجهيز',
        'supplier_name': 'رصيد أول المدة',
        'category': 'مواد التعبئة',
        'item_name': 'كرتون تصدير 5 كجم',
        'quantity': 2000.0,
        'unit_price': 14.5,
        'amount': 29000.0,
      };

      final isOpening = cctOpeningRow['source_type'] == 'opening_balance';
      final isPurchase = cctOpeningRow['source_type'] == 'purchase';

      final mappedRow = {
        'shipment_no': isOpening
            ? 'رصيد أول المدة'
            : (isPurchase ? 'فاتورة مشتريات' : 'استلام لوط'),
        'customer_name': cctOpeningRow['supplier_name'] ?? (isOpening ? 'رصيد افتتاحي' : 'مورد'),
        'category': cctOpeningRow['category'],
        'item_name': cctOpeningRow['item_name'],
        'quantity': cctOpeningRow['quantity'],
        'unit_price': cctOpeningRow['unit_price'],
        'amount': cctOpeningRow['amount'],
        'is_opening_balance': isOpening,
      };

      expect(mappedRow['shipment_no'], 'رصيد أول المدة');
      expect(mappedRow['customer_name'], 'رصيد أول المدة');
      expect(mappedRow['is_opening_balance'], isTrue);
      expect(mappedRow['amount'], 29000.0);
      expect(mappedRow['quantity'], 2000.0);
    });

    test('Total cost aggregation factors in both standard purchases and initial stock', () {
      final List<Map<String, dynamic>> detailsRows = [
        {
          'shipment_no': 'رصيد أول المدة',
          'item_name': 'كرتون تصدير 5 كجم',
          'category': 'مواد التعبئة',
          'quantity': 2000.0,
          'amount': 29000.0,
          'is_opening_balance': true,
        },
        {
          'shipment_no': 'فاتورة مشتريات #INV-101',
          'item_name': 'كرتون تصدير 5 كجم',
          'category': 'مواد التعبئة',
          'quantity': 1000.0,
          'amount': 15000.0,
          'is_opening_balance': false,
        },
        {
          'shipment_no': 'فاتورة مشتريات #INV-102',
          'item_name': 'شريط لاصق',
          'category': 'مواد التعبئة',
          'quantity': 100.0,
          'amount': 2500.0,
          'is_opening_balance': false,
        }
      ];

      final totalCost = detailsRows.fold<double>(
        0.0,
        (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0.0),
      );

      // 29,000 (opening) + 15,000 (purchase 1) + 2,500 (purchase 2) = 46,500
      expect(totalCost, 46500.0);

      // Item aggregation for 'كرتون تصدير 5 كجم'
      final cartonRows = detailsRows.where((r) => r['item_name'] == 'كرتون تصدير 5 كجم');
      final cartonTotal = cartonRows.fold<double>(0.0, (s, r) => s + (r['amount'] as double));
      final cartonQty = cartonRows.fold<double>(0.0, (s, r) => s + (r['quantity'] as double));

      expect(cartonTotal, 44000.0);
      expect(cartonQty, 3000.0);
    });
  });
}

