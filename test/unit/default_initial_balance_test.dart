import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/suppliers/supplier_cubit.dart';
import 'package:accounting_system/features/customers/customer_cubit.dart';
import 'package:accounting_system/features/transport_suppliers/transport_supplier_cubit.dart';
import 'package:accounting_system/features/clearing_agents/clearing_agent_cubit.dart';
import 'package:accounting_system/features/shipping_companies/shipping_company_cubit.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  group('Default Initial Balance (0.00) Across All Registration Forms', () {
    test('SupplierCubit defaults initialBalanceController to 0.00', () async {
      final cubit = SupplierCubit();
      expect(cubit.initialBalanceController.text, '0.00');

      // prepareAddForm resets to 0.00
      cubit.initialBalanceController.text = '555.00';
      await cubit.prepareAddForm();
      expect(cubit.initialBalanceController.text, '0.00');

      await cubit.close();
    });

    test('CustomerCubit defaults initialBalanceController to 0.00', () async {
      final cubit = CustomerCubit();
      expect(cubit.initialBalanceController.text, '0.00');

      cubit.initialBalanceController.text = '123.00';
      await cubit.prepareAddForm();
      expect(cubit.initialBalanceController.text, '0.00');

      await cubit.close();
    });

    test('TransportSupplierCubit defaults initialBalanceController to 0.00', () async {
      final cubit = TransportSupplierCubit();
      expect(cubit.initialBalanceController.text, '0.00');

      cubit.initialBalanceController.text = '999.00';
      await cubit.prepareAddForm();
      expect(cubit.initialBalanceController.text, '0.00');

      await cubit.close();
    });

    test('ClearingAgentCubit defaults initialBalanceController to 0.00', () async {
      final cubit = ClearingAgentCubit();
      expect(cubit.initialBalanceController.text, '0.00');

      cubit.initialBalanceController.text = '444.00';
      await cubit.prepareAddForm();
      expect(cubit.initialBalanceController.text, '0.00');

      await cubit.close();
    });

    test('ShippingCompanyCubit defaults initialBalanceController to 0.00', () async {
      final cubit = ShippingCompanyCubit();
      expect(cubit.initialBalanceController.text, '0.00');

      cubit.initialBalanceController.text = '777.00';
      await cubit.prepareAddForm();
      expect(cubit.initialBalanceController.text, '0.00');

      await cubit.close();
    });

    test('Empty or null text parsing defaults to 0.0', () {
      double parseBalance(String text) {
        return double.tryParse(text.trim()) ?? 0.0;
      }

      expect(parseBalance(''), 0.0);
      expect(parseBalance('   '), 0.0);
      expect(parseBalance('0.00'), 0.0);
      expect(parseBalance('150.50'), 150.50);
      expect(parseBalance('invalid'), 0.0);
    });
  });
}
