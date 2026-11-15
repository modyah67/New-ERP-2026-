import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/suppliers/supplier_account_statement_cubit.dart';
import 'package:accounting_system/data/services/account_ledger_service.dart';

void main() {
  group('Settlement Detailed Notes in Supplier & Account Statements', () {
    test('matchCostItemForSettlement matches by cost_item_id directly', () {
      final payment = {
        'id': '99',
        'reference_id': '501',
        'reference_type': 'cost_settlement',
        'description': 'تسوية تكلفة فعلية',
      };
      final costItem = {
        'id': 501,
        'packing_order_id': 12,
        'name': 'فرز وتدريج',
        'detailed_notes': 'توريد عمالة إضافية للفرز الليلي',
      };

      final matched = SupplierAccountStatementCubit.matchCostItemForSettlement(
        payment: payment,
        costItemsById: {'501': costItem},
        costItemsByOrderAndName: {},
        costItemsByOrder: {},
      );

      expect(matched, isNotNull);
      expect(matched!['id'], 501);
      expect(matched['detailed_notes'], 'توريد عمالة إضافية للفرز الليلي');
    });

    test('matchCostItemForSettlement matches by packing_order_id and item name in description', () {
      final payment = {
        'id': '100',
        'reference_id': '12',
        'reference_type': 'cost_settlement',
        'reference_text': 'INV-882',
        'description': 'تسوية تكلفة فعلية (زيادة) بند: عمالة وتعبئة (أمر PO-12)',
      };
      final item1 = {
        'id': 501,
        'packing_order_id': 12,
        'name': 'إيجار ثلاجة',
        'detailed_notes': 'ملاحظات أخرى',
      };
      final item2 = {
        'id': 502,
        'packing_order_id': 12,
        'name': 'عمالة وتعبئة',
        'detailed_notes': 'ساعات إضافية وتعبئة تصديرية - وردية ب',
        'invoice_ref': 'INV-882',
      };

      final matched = SupplierAccountStatementCubit.matchCostItemForSettlement(
        payment: payment,
        costItemsById: {},
        costItemsByOrderAndName: {
          '12_إيجار ثلاجة': item1,
          '12_عمالة وتعبئة': item2,
        },
        costItemsByOrder: {
          '12': [item1, item2],
        },
      );

      expect(matched, isNotNull);
      expect(matched!['id'], 502);
      expect(matched['detailed_notes'], 'ساعات إضافية وتعبئة تصديرية - وردية ب');
    });

    test('enrichSettlementStatementDetails appends detailed notes, invoice ref, qty, and unit price', () {
      final result = SupplierAccountStatementCubit.enrichSettlementStatementDetails(
        rawDesc: 'تسوية تكلفة فعلية (زيادة) بند: كرتون وتغليف (أمر 105)',
        fallbackDesc: 'تسوية تكلفة فعلية (زيادة) بند: كرتون وتغليف (أمر 105)',
        refId: '105',
        isCredit: true,
        amount: 2500.0,
        matchedCostItem: {
          'id': 701,
          'name': 'كرتون وتغليف',
          'actual_quantity': 50.0,
          'actual_unit_price': 50.0,
          'detailed_notes': 'فاتورة توريد عاجلة للموسم - خامات درجة أولى',
          'invoice_ref': 'F-9090',
        },
      );

      expect(result.description, contains('فاتورة توريد عاجلة للموسم - خامات درجة أولى'));
      expect(result.description, contains('مستند: F-9090'));
      expect(result.quantity, 50.0);
      expect(result.unitPrice, 50.0);
    });

    test('enrichSettlementStatementDetails replaces generic fallback when rawDesc is generic', () {
      final result = SupplierAccountStatementCubit.enrichSettlementStatementDetails(
        rawDesc: 'سند صرف للمورد',
        fallbackDesc: 'سند صرف للمورد',
        refId: '200',
        isCredit: false,
        amount: 1200.0,
        matchedCostItem: {
          'id': 801,
          'name': 'تخصيمات وزن فارغ',
          'actual_quantity': 10.0,
          'actual_unit_price': 0.0, // Should compute 1200 / 10 = 120.0
          'settlement_notes': 'خصم فرق وزن شاحنة 3412',
          'invoice_ref': '',
        },
      );

      expect(result.description, contains('تسوية تكلفة فعلية (وفر) بند: تخصيمات وزن فارغ'));
      expect(result.description, contains('خصم فرق وزن شاحنة 3412'));
      expect(result.quantity, 10.0);
      expect(result.unitPrice, 120.0);
    });

    test('enrichSettlementStatementDetails does not duplicate note if already in rawDesc', () {
      const note = 'ساعات عمل إضافية في التبريد';
      final result = SupplierAccountStatementCubit.enrichSettlementStatementDetails(
        rawDesc: 'تسوية تكلفة فعلية (زيادة) بند: تبريد (أمر 10) - $note - مستند: A-12',
        fallbackDesc: 'تسوية تكلفة فعلية (زيادة) بند: تبريد (أمر 10) - $note - مستند: A-12',
        refId: '10',
        isCredit: true,
        amount: 500.0,
        matchedCostItem: {
          'name': 'تبريد',
          'detailed_notes': note,
          'invoice_ref': 'A-12',
          'actual_quantity': 5.0,
          'actual_unit_price': 100.0,
        },
      );

      expect(note.allMatches(result.description).length, 1);
      expect('A-12'.allMatches(result.description).length, 1);
    });

    test('AccountLedgerService.enrichCostSettlementLedgerDescription enriches admin & general GL entries', () {
      final enriched = AccountLedgerService.enrichCostSettlementLedgerDescription(
        rawDescription: 'تسوية تكلفة مصاريف إدارية (أمر 45)',
        sourceType: 'packing_cost_settlement',
        orderItems: [
          {
            'name': 'مصاريف إدارية وإشراف',
            'detailed_notes': 'انتقالات ومبيت فريق الجودة بالمحطة',
            'invoice_ref': 'ADM-551',
          }
        ],
      );

      expect(enriched, contains('انتقالات ومبيت فريق الجودة بالمحطة'));
      expect(enriched, contains('مستند: ADM-551'));
    });

    test('AccountLedgerService.enrichCostSettlementLedgerDescription skips non-settlement entries', () {
      const orig = 'سداد فاتورة مورد عامة';
      final result = AccountLedgerService.enrichCostSettlementLedgerDescription(
        rawDescription: orig,
        sourceType: 'supplier_payment',
        orderItems: [
          {
            'name': 'صيانة',
            'detailed_notes': 'ملاحظة لا يجب إضافتها',
          }
        ],
      );

      expect(result, orig);
    });
  });
}

