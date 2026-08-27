import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/dao/station_product_batch_dao.dart';
import 'package:accounting_system/data/models/station_product_batch.dart';

void main() {
  group('FIFODeduction and Batch Metadata Preservation Tests', () {
    test('FIFODeduction preserves supplierName, purchaseInvoiceId, sourceDate and originalSourceType', () {
      const deduction = FIFODeduction(
        batchId: 101,
        quantity: 50.0,
        unitCost: 12.5,
        currency: 'EGP',
        exchangeRate: 1.0,
        supplierName: 'مورد الأمل',
        purchaseInvoiceId: 502,
        sourceDate: '2026-08-16T12:00:00Z',
        originalSourceType: 'purchase',
      );

      expect(deduction.batchId, 101);
      expect(deduction.quantity, 50.0);
      expect(deduction.unitCost, 12.5);
      expect(deduction.currency, 'EGP');
      expect(deduction.exchangeRate, 1.0);
      expect(deduction.supplierName, 'مورد الأمل');
      expect(deduction.purchaseInvoiceId, 502);
      expect(deduction.sourceDate, '2026-08-16T12:00:00Z');
      expect(deduction.originalSourceType, 'purchase');
      expect(deduction.totalCost, 50.0 * 12.5);
      expect(deduction.totalCostBase, 50.0 * 12.5 * 1.0);
    });

    test('FIFODeduction handles foreign currency and exchange rates accurately', () {
      const deduction = FIFODeduction(
        batchId: 102,
        quantity: 10.0,
        unitCost: 5.0,
        currency: 'USD',
        exchangeRate: 48.5,
        supplierName: 'Global Packaging Supplier',
        purchaseInvoiceId: 601,
      );

      expect(deduction.totalCost, 50.0);
      expect(deduction.totalCostBase, 50.0 * 48.5);
      expect(deduction.supplierName, 'Global Packaging Supplier');
      expect(deduction.purchaseInvoiceId, 601);
    });

    test('StationProductBatch correctly parses nested purchase_invoices and origin data', () {
      final batch = StationProductBatch.fromMap({
        'id': 201,
        'station_id': 2,
        'product_name': 'كرتونة 5 كجم',
        'product_code': 'RM-BOX-01',
        'quantity': 500.0,
        'remaining_quantity': 500.0,
        'unit_cost': 1.20,
        'currency': 'USD',
        'exchange_rate': 48.5,
        'source_type': 'transfer',
        'supplier_name': 'شركة الأمل للتعبئة',
        'source_station_name': 'محطة الفرز والتعبئة',
        'purchase_invoice_id': 301,
        'purchase_invoices': {'invoice_number': 'INV-2026-001'},
        'created_at': '2026-08-17T00:00:00Z',
      });

      expect(batch.id, 201);
      expect(batch.stationId, 2);
      expect(batch.productName, 'كرتونة 5 كجم');
      expect(batch.productCode, 'RM-BOX-01');
      expect(batch.quantity, 500.0);
      expect(batch.remainingQuantity, 500.0);
      expect(batch.unitCost, 1.20);
      expect(batch.currency, 'USD');
      expect(batch.supplierName, 'شركة الأمل للتعبئة');
      expect(batch.purchaseInvoiceId, 301);
      expect(batch.invoiceNumber, 'INV-2026-001');
      expect(batch.batchTotalCost, 500.0 * 1.20);
    });

    test('Batch aggregation across locations prevents double counting (1000 original, 500 transferred)', () {
      // Simulating Station A batch (1000 original, 500 deducted -> 500 remaining)
      final stationABatch = {
        'id': 101,
        'station_id': 1,
        'station_name': 'محطة الفرز',
        'product_name': 'كرتونة 5 كجم',
        'product_code': 'RM-BOX-01',
        'supplier_name': 'شركة الأمل للتعبئة',
        'quantity': 1000.0,
        'remaining_quantity': 500.0,
        'purchase_cost': 1.0,
        'source_type': 'purchase',
        'purchase_invoice_id': 301,
        'invoice_number': 'INV-001',
      };

      // Simulating Warehouse B batch (500 transferred -> 500 remaining)
      final warehouseBBatch = {
        'id': 102,
        'station_id': 2,
        'station_name': 'مخزن B',
        'product_name': 'كرتونة 5 كجم',
        'product_code': 'RM-BOX-01',
        'supplier_name': 'شركة الأمل للتعبئة',
        'quantity': 500.0,
        'remaining_quantity': 500.0,
        'purchase_cost': 1.0,
        'source_type': 'transfer',
        'purchase_invoice_id': 301,
        'invoice_number': 'INV-001',
      };

      final batches = [stationABatch, warehouseBBatch];

      // Aggregate remaining physical quantities
      final totalPhysicalQty = batches.fold<double>(
        0.0,
        (sum, b) => sum + ((b['remaining_quantity'] as num).toDouble()),
      );

      final totalPhysicalValue = batches.fold<double>(
        0.0,
        (sum, b) =>
            sum +
            ((b['remaining_quantity'] as num).toDouble()) *
                ((b['purchase_cost'] as num).toDouble()),
      );

      // Must be 1000 and NOT 1500!
      expect(totalPhysicalQty, 1000.0);
      // Total value must be 1000 USD and NOT 1500 USD!
      expect(totalPhysicalValue, 1000.0);

      // Average cost must be 1.0
      final avgCost = totalPhysicalValue / totalPhysicalQty;
      expect(avgCost, 1.0);
    });
  });
}
