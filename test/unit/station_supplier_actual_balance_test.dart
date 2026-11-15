import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/features/station_suppliers/cost_item_settlement_dialog.dart';
import 'package:accounting_system/features/suppliers/supplier_account_statement_cubit.dart';

void main() {
  group('Station & Deduction Suppliers: Approved Actual-Only Account Balance & Variance Decoupling', () {
    test('Station supplier saving scenario (expected 3,000 -> actual 2,500, variance -500): '
        'statement credit and final balance equal 2,500.0 EGP strictly (no 500 debit variance deduction)', () {
      final costItem = <String, dynamic>{
        'id': 101,
        'packing_order_id': 501,
        'supplier_id': 'taj-station-uuid',
        'name': 'تجهيز وتبريد وفرز',
        'cost_type': 'station',
        'cost_status': 'actual',
        'expected_amount': 3000.0,
        'base_amount': 3000.0,
        'actual_amount': 2500.0,
        'variance_amount': -500.0, // Analytical saving indicator only
        'reconciled_at': '2026-11-10T12:00:00Z',
        'variance_journal_entry_id': 9001,
        'detailed_notes': 'فاتورة محطة تاج شحنة رمان',
        'invoice_ref': 'INV-TAJ-01',
        'original_currency': 'EGP',
      };

      // Simulate legacy mixed entries (estimated 3,000 credit + saving -500 debit) OR clean migrated entry
      final legacyRawLedgerEntries = <Map<String, dynamic>>[
        {
          'id': 1,
          'entity_id': 'taj-station-uuid',
          'amount': 3000.0,
          'currency': 'EGP',
          'entry_type': 'credit',
          'reference_id': '501',
          'reference_type': 'packing_cost',
          'reference_text': 'تجهيز وتبريد وفرز',
          'description': 'بند تكلفة أمر 501: تجهيز وتبريد وفرز',
          'created_at': '2026-11-08T10:00:00Z',
        },
        {
          'id': 2,
          'entity_id': 'taj-station-uuid',
          'amount': 500.0,
          'currency': 'EGP',
          'entry_type': 'debit',
          'reference_id': '501',
          'reference_type': 'cost_settlement',
          'reference_text': 'INV-TAJ-01',
          'description': 'تسوية تكلفة فعلية (وفر) بند: تجهيز وتبريد وفرز',
          'created_at': '2026-11-10T12:00:00Z',
        },
      ];

      final normalized = SupplierAccountStatementCubit.normalizeDualCostSupplierLedgerEntries(
        rawEntries: legacyRawLedgerEntries,
        costItemsById: {'101': costItem},
        costItemsByOrderAndName: {'501_تجهيز وتبريد وفرز': costItem},
        costItemsByOrder: {'501': [costItem]},
        isDualCostSupplier: true,
      );

      // Must collapse to ONE credit row equal strictly to actual_amount = 2,500 (zero debit variance row)
      expect(normalized.length, equals(1));
      expect(normalized.first['entry_type'], equals('credit'));
      expect(normalized.first['amount'], equals(2500.0));
      expect(normalized.first['description'].toString(), contains('اعتماد تكلفة فعلية'));

      final enriched = SupplierAccountStatementCubit.enrichSettlementStatementDetails(
        rawDesc: normalized.first['description'].toString(),
        fallbackDesc: 'اعتماد تكلفة فعلية للمورد',
        refId: '501',
        isCredit: true,
        amount: 2500.0,
        matchedCostItem: costItem,
      );
      expect(enriched.description, contains('فاتورة محطة تاج شحنة رمان'));
      expect(enriched.description, contains('INV-TAJ-01'));

      // Live DAO calculation must match 2,500.0 EGP identically
      final perCurrency = <String, Map<String, double>>{};
      SupplierDao.applyLedgerEntriesToCurrencyBalances(
        ledgerTxs: legacyRawLedgerEntries,
        perCurrency: perCurrency,
        treasuryTxIds: const {},
        bankTxIds: const {},
        dualCostSupplierKeys: const {'taj-station-uuid', '85001'},
        aliasToCanonicalId: const {'taj-station-uuid': 'taj-station-uuid', '85001': 'taj-station-uuid'},
        costItems: [costItem],
      );

      expect(perCurrency['taj-station-uuid']?['EGP'], equals(2500.0));
    });

    test('Station supplier overrun scenario (expected 2,000 -> actual 2,500, variance +500): '
        'statement credit and final balance equal 2,500.0 EGP strictly', () {
      final costItem = <String, dynamic>{
        'id': 102,
        'packing_order_id': 502,
        'supplier_id': 'taj-station-uuid',
        'name': 'تخليص وتعبئة',
        'cost_type': 'station',
        'cost_status': 'actual',
        'expected_amount': 2000.0,
        'base_amount': 2000.0,
        'actual_amount': 2500.0,
        'variance_amount': 500.0, // Analytical overrun indicator only
        'reconciled_at': '2026-11-10T14:00:00Z',
        'variance_journal_entry_id': 9002,
        'original_currency': 'EGP',
      };

      final legacyRawEntries = <Map<String, dynamic>>[
        {
          'id': 3,
          'entity_id': 'taj-station-uuid',
          'amount': 2000.0,
          'currency': 'EGP',
          'entry_type': 'credit',
          'reference_id': '502',
          'reference_type': 'packing_cost',
          'description': 'بند تكلفة أمر 502: تخليص وتعبئة',
          'created_at': '2026-11-09T09:00:00Z',
        },
        {
          'id': 4,
          'entity_id': 'taj-station-uuid',
          'amount': 500.0,
          'currency': 'EGP',
          'entry_type': 'credit',
          'reference_id': '502',
          'reference_type': 'cost_settlement',
          'description': 'تسوية تكلفة فعلية (زيادة) بند: تخليص وتعبئة',
          'created_at': '2026-11-10T14:00:00Z',
        },
      ];

      final normalized = SupplierAccountStatementCubit.normalizeDualCostSupplierLedgerEntries(
        rawEntries: legacyRawEntries,
        costItemsById: {'102': costItem},
        costItemsByOrderAndName: {'502_تخليص وتعبئة': costItem},
        costItemsByOrder: {'502': [costItem]},
        isDualCostSupplier: true,
      );

      expect(normalized.length, equals(1));
      expect(normalized.first['entry_type'], equals('credit'));
      expect(normalized.first['amount'], equals(2500.0));

      final perCurrency = <String, Map<String, double>>{};
      SupplierDao.applyLedgerEntriesToCurrencyBalances(
        ledgerTxs: legacyRawEntries,
        perCurrency: perCurrency,
        treasuryTxIds: const {},
        bankTxIds: const {},
        dualCostSupplierKeys: const {'taj-station-uuid'},
        aliasToCanonicalId: const {'taj-station-uuid': 'taj-station-uuid'},
        costItems: [costItem],
      );

      expect(perCurrency['taj-station-uuid']?['EGP'], equals(2500.0));
    });

    test('Unsettled estimated costs and legacy Stage-3 false auto-locks have 0 financial impact on supplier balance', () {
      final unsettledExpectedItem = <String, dynamic>{
        'id': 201,
        'packing_order_id': 601,
        'supplier_id': 'taj-station-uuid',
        'name': 'تجهيز تقديري لم يُسوَّ',
        'cost_status': 'expected',
        'expected_amount': 3000.0,
        'base_amount': 3000.0,
        'actual_amount': null,
        'reconciled_at': null,
        'variance_journal_entry_id': null,
        'original_currency': 'EGP',
      };

      // Legacy falsely auto-locked row (cost_status='actual' without any settlement evidence)
      final falseAutoLockedItem = <String, dynamic>{
        'id': 202,
        'packing_order_id': 602,
        'supplier_id': 'taj-station-uuid',
        'name': 'تبريد معلق',
        'cost_status': 'actual',
        'expected_amount': 1200.0,
        'base_amount': 1200.0,
        'actual_amount': 1200.0,
        'reconciled_at': null,
        'variance_journal_entry_id': null,
        'invoice_ref': null,
        'settlement_notes': null,
        'detailed_notes': null,
        'original_currency': 'EGP',
      };

      final rawEntries = <Map<String, dynamic>>[
        {
          'id': 11,
          'entity_id': 'taj-station-uuid',
          'amount': 3000.0,
          'currency': 'EGP',
          'entry_type': 'credit',
          'reference_id': '601',
          'reference_type': 'packing_cost',
          'description': 'بند تكلفة أمر 601: تجهيز تقديري لم يُسوَّ',
        },
        {
          'id': 12,
          'entity_id': 'taj-station-uuid',
          'amount': 1200.0,
          'currency': 'EGP',
          'entry_type': 'credit',
          'reference_id': '602',
          'reference_type': 'packing_cost',
          'description': 'بند تكلفة أمر 602: تبريد معلق',
        },
      ];

      final normalized = SupplierAccountStatementCubit.normalizeDualCostSupplierLedgerEntries(
        rawEntries: rawEntries,
        costItemsById: {'201': unsettledExpectedItem, '202': falseAutoLockedItem},
        costItemsByOrderAndName: {
          '601_تجهيز تقديري لم يُسوَّ': unsettledExpectedItem,
          '602_تبريد معلق': falseAutoLockedItem,
        },
        costItemsByOrder: {
          '601': [unsettledExpectedItem],
          '602': [falseAutoLockedItem],
        },
        isDualCostSupplier: true,
      );
      expect(normalized, isEmpty);

      final perCurrency = <String, Map<String, double>>{};
      SupplierDao.applyLedgerEntriesToCurrencyBalances(
        ledgerTxs: rawEntries,
        perCurrency: perCurrency,
        treasuryTxIds: const {},
        bankTxIds: const {},
        dualCostSupplierKeys: const {'taj-station-uuid'},
        aliasToCanonicalId: const {'taj-station-uuid': 'taj-station-uuid'},
        costItems: [unsettledExpectedItem, falseAutoLockedItem],
      );
      expect(perCurrency['taj-station-uuid']?['EGP'] ?? 0.0, equals(0.0));
    });

    test('Payments & date-filtered opening balances deduct strictly against approved actual costs only', () {
      final settledItem = <String, dynamic>{
        'id': 301,
        'packing_order_id': 701,
        'supplier_id': 'taj-station-uuid',
        'name': 'خدمة محطة',
        'cost_status': 'actual',
        'expected_amount': 3000.0,
        'actual_amount': 2500.0,
        'reconciled_at': '2026-11-05T10:00:00Z',
        'variance_journal_entry_id': 9101,
        'original_currency': 'EGP',
      };

      // Shared dedup set across prior (opening balance) and current period prevents split-date double counting
      final sharedEmittedIds = <String>{};

      final priorNormalized = SupplierAccountStatementCubit.normalizeDualCostSupplierLedgerEntries(
        rawEntries: [
          {
            'id': 20,
            'entity_id': 'taj-station-uuid',
            'amount': 3000.0,
            'currency': 'EGP',
            'entry_type': 'credit',
            'reference_id': '701',
            'reference_type': 'packing_cost',
            'currency_snapshot': {'cost_item_id': 301},
          },
        ],
        costItemsById: {'301': settledItem},
        costItemsByOrderAndName: {'701_خدمة محطة': settledItem},
        costItemsByOrder: {'701': [settledItem]},
        isDualCostSupplier: true,
        emittedCostItemIds: sharedEmittedIds,
      );

      final currentNormalized = SupplierAccountStatementCubit.normalizeDualCostSupplierLedgerEntries(
        rawEntries: [
          {
            'id': 21,
            'entity_id': 'taj-station-uuid',
            'amount': 500.0,
            'currency': 'EGP',
            'entry_type': 'debit',
            'reference_id': '701',
            'reference_type': 'cost_settlement',
            'currency_snapshot': {'cost_item_id': 301},
            'description': 'تسوية تكلفة فعلية (وفر)',
          },
          {
            'id': 22,
            'entity_id': 'taj-station-uuid',
            'amount': 1000.0,
            'currency': 'EGP',
            'entry_type': 'debit',
            'reference_id': '999',
            'reference_type': 'supplier_payment',
            'description': 'سند صرف دفعة للمورد',
          },
        ],
        costItemsById: {'301': settledItem},
        costItemsByOrderAndName: {'701_خدمة محطة': settledItem},
        costItemsByOrder: {'701': [settledItem]},
        isDualCostSupplier: true,
        emittedCostItemIds: sharedEmittedIds,
      );

      // Opening balance carries actual 2,500; current period must NOT emit 500 saving or duplicate 2,500!
      expect(priorNormalized.length, equals(1));
      expect(priorNormalized.first['amount'], equals(2500.0));
      expect(currentNormalized.length, equals(1));
      expect(currentNormalized.first['reference_type'], equals('supplier_payment'));
      expect(currentNormalized.first['amount'], equals(1000.0));

      // Live DAO total with payment = 2,500 credit - 1,000 debit = 1,500 EGP
      final perCurrency = <String, Map<String, double>>{};
      SupplierDao.applyLedgerEntriesToCurrencyBalances(
        ledgerTxs: [
          {
            'id': 20,
            'entity_id': 'taj-station-uuid',
            'amount': 3000.0,
            'currency': 'EGP',
            'entry_type': 'credit',
            'reference_type': 'packing_cost',
          },
          {
            'id': 21,
            'entity_id': 'taj-station-uuid',
            'amount': 500.0,
            'currency': 'EGP',
            'entry_type': 'debit',
            'reference_type': 'cost_settlement',
          },
          {
            'id': 22,
            'entity_id': 'taj-station-uuid',
            'amount': 1000.0,
            'currency': 'EGP',
            'entry_type': 'debit',
            'reference_id': 'tx-cash-1',
            'reference_type': 'supplier_payment',
          },
        ],
        perCurrency: perCurrency,
        treasuryTxIds: const {},
        bankTxIds: const {},
        dualCostSupplierKeys: const {'taj-station-uuid'},
        aliasToCanonicalId: const {'taj-station-uuid': 'taj-station-uuid'},
        costItems: [settledItem],
      );
      expect(perCurrency['taj-station-uuid']?['EGP'], equals(1500.0));
    });

    test('CostItemSettlementDialog.computeProjectedSupplierBalance adds strictly actual cost (or delta on amend)', () {
      // Unsettled item (expected 3,000, current balance 0): settling 2,500 projects 2,500 (not 0 - 500 or 3,000 - 500)
      expect(
        CostItemSettlementDialog.computeProjectedSupplierBalance(
          currentBalance: 0.0,
          enteredActualCost: 2500.0,
          isAlreadySettled: false,
        ),
        equals(2500.0),
      );

      // Already has 1,000 balance from previous orders -> settling 2,500 projects 3,500
      expect(
        CostItemSettlementDialog.computeProjectedSupplierBalance(
          currentBalance: 1000.0,
          enteredActualCost: 2500.0,
          isAlreadySettled: false,
        ),
        equals(3500.0),
      );

      // Amending already-settled item from 2,500 -> 2,800 adjusts strictly by +300
      expect(
        CostItemSettlementDialog.computeProjectedSupplierBalance(
          currentBalance: 2500.0,
          enteredActualCost: 2800.0,
          isAlreadySettled: true,
          previousActualAmount: 2500.0,
        ),
        equals(2800.0),
      );
    });

    test('Non-dual-cost suppliers keep existing behavior unaffected', () {
      final rawEntries = [
        {
          'id': 1,
          'entity_id': 'transport-uuid',
          'amount': 1500.0,
          'currency': 'EGP',
          'entry_type': 'credit',
          'reference_type': 'packing_cost',
        },
        {
          'id': 2,
          'entity_id': 'transport-uuid',
          'amount': 200.0,
          'currency': 'EGP',
          'entry_type': 'debit',
          'reference_type': 'cost_settlement',
        },
      ];

      expect(SupplierModel.isEgpOnlyCategoryOrCode('transport', '20001'), isFalse);

      final normalized = SupplierAccountStatementCubit.normalizeDualCostSupplierLedgerEntries(
        rawEntries: rawEntries,
        costItemsById: const {},
        costItemsByOrderAndName: const {},
        costItemsByOrder: const {},
        isDualCostSupplier: false,
      );
      expect(normalized.length, equals(2));
    });
  });
}

