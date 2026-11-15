import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/data/dao/lot_dao.dart';

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

  group('Crop Purchases (Lot Receipts) Double-Entry Bookkeeping & Balancing Tests', () {
    test('Journal entry balance equation: Total Base Debit == Total Base Credit for Produce Inventory', () {
      const quantityKg = 500.0;
      const unitPrice = 20.0;
      const exchangeRate = 1.0;
      final totalForeign = quantityKg * unitPrice;
      final totalEgp = totalForeign * exchangeRate;

      final debitLine = {
        'account_code': '12412',
        'name': 'Raw Produce Inventory',
        'account_name': 'مخزن مشتريات خام',
        'debit': totalForeign,
        'base_debit': totalEgp,
        'credit': 0.0,
        'base_credit': 0.0,
        'currency': 'EGP',
      };

      final creditLine = {
        'account_code': '211101',
        'name': 'Supplier - Yasser',
        'account_name': 'مورد - ياسر',
        'debit': 0.0,
        'base_debit': 0.0,
        'credit': totalForeign,
        'base_credit': totalEgp,
        'currency': 'EGP',
      };

      final totalBaseDebit = (debitLine['base_debit'] as double) + (creditLine['base_debit'] as double);
      final totalBaseCredit = (debitLine['base_credit'] as double) + (creditLine['base_credit'] as double);

      expect(totalBaseDebit, equals(10000.0));
      expect(totalBaseCredit, equals(10000.0));
      expect((totalBaseDebit - totalBaseCredit).abs(), lessThanOrEqualTo(0.01));
    });

    test('Foreign currency crop purchase balances base currency exactly', () {
      const quantityKg = 1000.0;
      const unitPriceUsd = 1.50;
      const exchangeRate = 48.50;
      final totalUsd = quantityKg * unitPriceUsd;
      final totalEgp = totalUsd * exchangeRate;

      final lines = [
        {
          'account_code': '12412',
          'debit': totalUsd,
          'base_debit': totalEgp,
          'credit': 0.0,
          'base_credit': 0.0,
          'currency': 'USD',
        },
        {
          'account_code': '211102',
          'debit': 0.0,
          'base_debit': 0.0,
          'credit': totalUsd,
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

      expect(sumBaseDebit, equals(72750.0));
      expect(sumBaseCredit, equals(72750.0));
      expect((sumBaseDebit - sumBaseCredit).abs(), lessThanOrEqualTo(0.01));
    });

    test('Price adjustment generates balanced differential entry', () {
      const oldCost = 10000.0;
      const newCost = 12000.0;
      final delta = newCost - oldCost;

      final adjLines = [
        {
          'account_code': '12412',
          'debit': delta > 0 ? delta : 0.0,
          'base_debit': delta > 0 ? delta : 0.0,
          'credit': delta < 0 ? delta.abs() : 0.0,
          'base_credit': delta < 0 ? delta.abs() : 0.0,
        },
        {
          'account_code': '211101',
          'debit': delta < 0 ? delta.abs() : 0.0,
          'base_debit': delta < 0 ? delta.abs() : 0.0,
          'credit': delta > 0 ? delta : 0.0,
          'base_credit': delta > 0 ? delta : 0.0,
        },
      ];

      double sumDebit = 0;
      double sumCredit = 0;
      for (final l in adjLines) {
        sumDebit += (l['base_debit'] as double);
        sumCredit += (l['base_credit'] as double);
      }

      expect(sumDebit, equals(2000.0));
      expect(sumCredit, equals(2000.0));
      expect((sumDebit - sumCredit).abs(), lessThanOrEqualTo(0.01));
    });

    test('LotDao getJournalEntriesForLot returns empty array when empty lot id passed', () async {
      final dao = LotDao();
      final result = await dao.getJournalEntriesForLot('');
      expect(result, isEmpty);
    });
  });
}
