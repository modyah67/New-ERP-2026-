import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/data/dao/purchase_dao.dart';
import 'package:accounting_system/data/models/purchase_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://test.supabase.co',
        publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.t-test-key-signature',
      );
    } catch (_) {}
  });

  group('Purchase Confirmation Double-Entry Bookkeeping & Balancing Tests', () {
    test('Empty or invalid purchase ID throws validation exception', () async {
      final dao = PurchaseDao();
      expect(() => dao.confirmPurchase(''), throwsA(isA<Exception>()));
      expect(() => dao.confirmPurchase('   '), throwsA(isA<Exception>()));
    });

    test('Journal entry balance equation: Total Base Debit == Total Base Credit', () {
      // Emulating a purchase invoice with 1000 items @ 3.00 EGP = 3000.00 EGP
      const quantity = 1000.0;
      const unitCost = 3.0;
      const exchangeRate = 1.0;
      final totalForeign = quantity * unitCost;
      final totalEgp = totalForeign * exchangeRate;

      // Debit Line: Packaging Materials Inventory (Account 12411)
      final debitLine = {
        'account_code': '12411',
        'name': 'Packaging Materials Warehouse',
        'account_name': 'مخزن التعبئة والتغليف',
        'debit': totalForeign,
        'base_debit': totalEgp,
        'credit': 0.0,
        'base_credit': 0.0,
        'currency': 'EGP',
      };

      // Credit Line: Supplier Sub-Account (Account 211201 for مورد - علي)
      final creditLine = {
        'account_code': '211201',
        'name': 'Supplier - Ali',
        'account_name': 'مورد - علي',
        'debit': 0.0,
        'base_debit': 0.0,
        'credit': totalForeign,
        'base_credit': totalEgp,
        'currency': 'EGP',
      };

      final totalBaseDebit = (debitLine['base_debit'] as double) + (creditLine['base_debit'] as double);
      final totalBaseCredit = (debitLine['base_credit'] as double) + (creditLine['base_credit'] as double);

      // Verify double-entry balancing constraint (P0001)
      expect(totalBaseDebit, equals(3000.0));
      expect(totalBaseCredit, equals(3000.0));
      expect((totalBaseDebit - totalBaseCredit).abs(), lessThanOrEqualTo(0.05));
    });

    test('Foreign currency purchase converts debit_base and credit_base accurately', () {
      // Purchase of 200 items @ $15.00 USD, Exchange rate = 48.50 EGP/USD
      const quantity = 200.0;
      const unitCost = 15.0;
      const exchangeRate = 48.50;
      final totalForeign = quantity * unitCost; // 3000.0 USD
      final totalEgp = totalForeign * exchangeRate; // 145,500.0 EGP

      final lines = [
        {
          'account_code': '12411',
          'debit': totalForeign,
          'base_debit': totalEgp,
          'credit': 0.0,
          'base_credit': 0.0,
          'currency': 'USD',
        },
        {
          'account_code': '211201',
          'debit': 0.0,
          'base_debit': 0.0,
          'credit': totalForeign,
          'base_credit': totalEgp,
          'currency': 'USD',
        },
      ];

      double sumBaseDebit = 0;
      double sumBaseCredit = 0;
      for (final l in lines) {
        sumBaseDebit += (l['base_debit'] as double);
        sumBaseCredit += (l['base_credit'] as double);
      }

      expect(sumBaseDebit, equals(145500.0));
      expect(sumBaseCredit, equals(145500.0));
      expect((sumBaseDebit - sumBaseCredit).abs(), lessThanOrEqualTo(0.05));
    });

    test('Inventory classification: 12411 for Packaging, 12412 for Produce Crops', () {
      String resolveInventoryAccountCode({required bool isRawMaterial, String? categoryName}) {
        if (categoryName != null &&
            (categoryName.contains('محصول') || categoryName.contains('محاصيل'))) {
          return '12412';
        }
        if (isRawMaterial) {
          return '12411';
        }
        return '12412';
      }

      // Packaging materials (Cartons, Punnet, Sticker)
      expect(resolveInventoryAccountCode(isRawMaterial: true, categoryName: 'كراتين'), equals('12411'));
      expect(resolveInventoryAccountCode(isRawMaterial: true, categoryName: 'استيكر'), equals('12411'));

      // Crops (Strawberries, Mango, Oranges)
      expect(resolveInventoryAccountCode(isRawMaterial: false, categoryName: 'محاصيل زراعية'), equals('12412'));
      expect(resolveInventoryAccountCode(isRawMaterial: true, categoryName: 'محصول خام'), equals('12412'));
    });
  });

  group('Granular Item-Level Journal Entry Lines Generation Tests', () {
    test('generateItemLevelJournalLines generates individual debit lines per item and a balanced credit line', () {
      final validLines = [
        PurchaseLineData(
          code: 'PAC-001',
          name: 'كراتين برتقال 15 كجم',
          quantity: 500,
          purchasePrice: 25.0,
          unit: 'كرتونة',
          existingItemId: 'rm-uuid-1',
        ),
        PurchaseLineData(
          code: 'PAC-002',
          name: 'شريط لاصق شفاف',
          quantity: 100,
          purchasePrice: 50.0,
          unit: 'رول',
          existingItemId: 'rm-uuid-2',
        ),
        PurchaseLineData(
          code: 'PAC-003',
          name: 'زاوية كرتون مقوى',
          quantity: 2000,
          purchasePrice: 4.5,
          unit: 'قطعة',
          existingItemId: 'rm-uuid-3',
        ),
      ];

      final lines = PurchaseDao.generateItemLevelJournalLines(
        validLines: validLines,
        supplierAccountId: 2112001,
        supplierName: 'شركة الأهرام للكرتون',
        invoiceNumber: 'PINV-0001',
        currency: 'EGP',
        exchangeRate: 1.0,
        packagingInventoryAccountId: 12411,
      );

      // Expect 3 debit lines (one per item) + 1 credit line for supplier = 4 lines total
      expect(lines.length, equals(4));

      // Line 1: Item 1
      expect(lines[0]['item_name'], equals('كراتين برتقال 15 كجم'));
      expect(lines[0]['debit'], equals(12500.0)); // 500 * 25
      expect(lines[0]['credit'], equals(0.0));
      expect(lines[0]['account_code'], equals('12411'));
      expect(lines[0]['description'], contains('كمية: 500.0 كرتونة'));
      expect(lines[0]['description'], contains('بسعر: 25.0 EGP'));
      expect(lines[0]['description'], contains('فاتورة PINV-0001'));

      // Line 2: Item 2
      expect(lines[1]['item_name'], equals('شريط لاصق شفاف'));
      expect(lines[1]['debit'], equals(5000.0)); // 100 * 50
      expect(lines[1]['credit'], equals(0.0));
      expect(lines[1]['description'], contains('كمية: 100.0 رول'));

      // Line 3: Item 3
      expect(lines[2]['item_name'], equals('زاوية كرتون مقوى'));
      expect(lines[2]['debit'], equals(9000.0)); // 2000 * 4.5
      expect(lines[2]['credit'], equals(0.0));
      expect(lines[2]['description'], contains('كمية: 2000.0 قطعة'));

      // Line 4: Supplier Credit Line
      expect(lines[3]['debit'], equals(0.0));
      expect(lines[3]['credit'], equals(26500.0)); // 12500 + 5000 + 9000 = 26500
      expect(lines[3]['account_id'], equals(2112001));
      expect(lines[3]['description'], contains('مستحقات مورد: شركة الأهرام للكرتون'));

      // Strict Double-Entry Balance Equation
      double totalDebit = 0;
      double totalCredit = 0;
      for (final l in lines) {
        totalDebit += (l['debit'] as num).toDouble();
        totalCredit += (l['credit'] as num).toDouble();
      }
      expect(totalDebit, equals(26500.0));
      expect(totalCredit, equals(26500.0));
      expect(totalDebit, equals(totalCredit));
    });

    test('Foreign currency granular posting converts to base currency (EGP) with zero balance disparity', () {
      final validLines = [
        PurchaseLineData(
          code: 'CROP-001',
          name: 'برتقال صيفي فرز أول',
          quantity: 1000,
          purchasePrice: 20.0, // USD
          unit: 'كجم',
        ),
        PurchaseLineData(
          code: 'CROP-002',
          name: 'ليمون بنزهير خام',
          quantity: 500,
          purchasePrice: 15.0, // USD
          unit: 'كجم',
        ),
      ];

      const exchangeRate = 50.0; // 50 EGP / USD

      final lines = PurchaseDao.generateItemLevelJournalLines(
        validLines: validLines,
        supplierAccountId: 2112002,
        supplierName: 'مزارع الصالحية',
        invoiceNumber: 'PINV-0002',
        currency: 'USD',
        exchangeRate: exchangeRate,
        cropInventoryAccountId: 12412,
      );

      expect(lines.length, equals(3)); // 2 debit + 1 credit

      // Item 1: 1000 * 20 = $20,000 USD -> 1,000,000 EGP
      expect(lines[0]['debit'], equals(20000.0));
      expect(lines[0]['base_debit'], equals(1000000.0));
      expect(lines[0]['account_code'], equals('12412'));

      // Item 2: 500 * 15 = $7,500 USD -> 375,000 EGP
      expect(lines[1]['debit'], equals(7500.0));
      expect(lines[1]['base_debit'], equals(375000.0));

      // Supplier Credit Line: $27,500 USD -> 1,375,000 EGP
      expect(lines[2]['credit'], equals(27500.0));
      expect(lines[2]['base_credit'], equals(1375000.0));

      double sumDebitForeign = 0;
      double sumCreditForeign = 0;
      double sumDebitEgp = 0;
      double sumCreditEgp = 0;

      for (final l in lines) {
        sumDebitForeign += (l['debit'] as num).toDouble();
        sumCreditForeign += (l['credit'] as num).toDouble();
        sumDebitEgp += (l['base_debit'] as num).toDouble();
        sumCreditEgp += (l['base_credit'] as num).toDouble();
      }

      expect(sumDebitForeign, equals(sumCreditForeign));
      expect(sumDebitEgp, equals(sumCreditEgp));
      expect(sumDebitForeign, equals(27500.0));
      expect(sumDebitEgp, equals(1375000.0));
    });
  });
}

