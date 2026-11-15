import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';

void main() {
  group('Multi-Currency Current Balance Display Tests', () {
    test('Displays distinct per-currency balances without merging into single currency', () {
      final supplier = SupplierModel(
        id: 'sup-1',
        supplierCode: '50001',
        name: 'المورد المتعدد',
        currency: 'MULTI',
        isMultiCurrency: true,
        supportedCurrencies: const ['EGP', 'USD', 'EUR', 'GBP'],
        initialBalancesByCurrency: const {
          'EGP': SupplierCurrencyBalance(currency: 'EGP', amount: 100.0, direction: 'CREDIT', exchangeRate: 1.0),
          'USD': SupplierCurrencyBalance(currency: 'USD', amount: 100.0, direction: 'CREDIT', exchangeRate: 50.0),
          'EUR': SupplierCurrencyBalance(currency: 'EUR', amount: 100.0, direction: 'CREDIT', exchangeRate: 55.0),
          'GBP': SupplierCurrencyBalance(currency: 'GBP', amount: 100.0, direction: 'CREDIT', exchangeRate: 65.0),
        },
        currentBalancesByCurrency: const {
          'EGP': 100.0,
          'USD': 100.0,
          'EUR': 100.0,
          'GBP': 100.0,
        },
        outstandingBalance: 17100.0,
      );

      final currentFormatted = supplier.formattedCurrentBalance;
      expect(currentFormatted.contains('100 ج.م'), true, reason: 'Must contain EGP balance');
      expect(currentFormatted.contains('100 \$'), true, reason: 'Must contain USD balance');
      expect(currentFormatted.contains('100 €'), true, reason: 'Must contain EUR balance');
      expect(currentFormatted.contains('100 £'), true, reason: 'Must contain GBP balance');
      expect(currentFormatted.contains(' + '), true, reason: 'Must separate currencies with plus');
    });

    test('Handles partial currency payments and negative (advance) balances', () {
      final supplier = SupplierModel(
        id: 'sup-2',
        supplierCode: '50000',
        name: 'مورد حركات متعددة',
        currency: 'MULTI',
        isMultiCurrency: true,
        supportedCurrencies: const ['EGP', 'USD', 'EUR', 'GBP'],
        currentBalancesByCurrency: const {
          'EGP': -100.0, // Advance payment
          'USD': 150.0,
          'EUR': 0.0,    // Fully settled
          'GBP': 50.0,
        },
        outstandingBalance: 2500.0,
      );

      final currentFormatted = supplier.formattedCurrentBalance;
      expect(currentFormatted.contains('-100 ج.م'), true, reason: 'Must show negative sign for advance');
      expect(currentFormatted.contains('150 \$'), true, reason: 'Must show 150 USD');
      expect(currentFormatted.contains('50 £'), true, reason: 'Must show 50 GBP');
      expect(currentFormatted.contains('0 €'), false, reason: 'Settled 0 currency should not clutter multi display');
    });

    test('Returns 0.00 when all currencies are fully paid', () {
      final supplier = SupplierModel(
        id: 'sup-3',
        supplierCode: '50002',
        name: 'مورد مسدد بالكامل',
        currency: 'MULTI',
        isMultiCurrency: true,
        supportedCurrencies: const ['EGP', 'USD', 'EUR'],
        currentBalancesByCurrency: const {
          'EGP': 0.0,
          'USD': 0.0,
          'EUR': 0.0,
        },
        outstandingBalance: 0.0,
      );

      expect(supplier.formattedCurrentBalance, '0.00');
    });
  });
}
