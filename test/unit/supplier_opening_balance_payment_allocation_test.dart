import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/supabase_options.dart';
import 'package:accounting_system/data/dao/payment_dao.dart';

void main() {
  group('Supplier Opening Balance Payment Allocation Tests', () {
    test('Calculates remaining opening balance deterministically from allocations', () {
      // Scenario 1: Initial 100 EUR, paid 100 EUR
      const initialPayable = 100.0;
      const paidOpening = 100.0;
      final remainingOpening = max(0.0, initialPayable - paidOpening);
      expect(remainingOpening, 0.0);

      // Even if curBal is null (filtered out by HAVING sum <> 0 in DB)
      double? curBal;
      double openingRemaining = 0.0;
      if (remainingOpening > 0) {
        if (curBal != null) {
          openingRemaining = min(remainingOpening, curBal);
        } else {
          openingRemaining = paidOpening > 0 ? 0.0 : remainingOpening;
        }
      }
      expect(openingRemaining, 0.0, reason: 'Opening balance must disappear on first full payment');

      // Scenario 2: Initial 100 EUR, paid 40 EUR partially
      const partialPaid = 40.0;
      final remainingPartial = max(0.0, initialPayable - partialPaid);
      expect(remainingPartial, 60.0);
      curBal = 60.0;
      if (remainingPartial > 0) {
        if (curBal != null) {
          openingRemaining = min(remainingPartial, curBal);
        }
      }
      expect(openingRemaining, 60.0);

      // Scenario 3: Initial 100 EUR, untouched (0 paid)
      const zeroPaid = 0.0;
      final remainingUntouched = max(0.0, initialPayable - zeroPaid);
      expect(remainingUntouched, 100.0);
    });

    test('Live DB test: getOpeningBalancePaid fetches recorded allocations correctly', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: SupabaseOptions.url,
        anonKey: SupabaseOptions.anonKey,
      );

      final client = Supabase.instance.client;
      await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

      final paymentDao = PaymentDao();
      const supplierId = '26a0f791-a509-4be1-9620-008d1c17c079';

      final paidMap = await paymentDao.getOpeningBalancePaid('supplier', supplierId);
      print('Fetched paid opening balances: $paidMap');

      expect(paidMap.containsKey('EUR'), true);
      expect(paidMap['EUR'], 100.0);
      expect(paidMap.containsKey('USD'), true);
      expect(paidMap['USD'], 100.0);
      expect(paidMap.containsKey('EGP'), true);
      expect(paidMap['EGP'], 100.0);
    });
  });
}
