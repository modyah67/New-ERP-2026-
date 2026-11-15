import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/data/models/purchase_model.dart';
import 'package:accounting_system/features/purchases/purchase_state.dart';

void main() {
  group('Purchase Form Currency & Exchange Rate Integration Tests', () {
    test('PurchaseFormState defaults to EGP with exchange rate 1.0', () {
      final state = PurchaseFormState(purchaseDate: DateTime.now());
      expect(state.invoiceCurrency, 'EGP');
      expect(state.exchangeRate, 1.0);
      expect(state.selectedSupplier, isNull);
    });

    test('PurchaseFormState.copyWith updates invoiceCurrency and exchangeRate correctly', () {
      final state = PurchaseFormState(purchaseDate: DateTime.now());
      final updated = state.copyWith(
        invoiceCurrency: 'USD',
        exchangeRate: 50.25,
      );

      expect(updated.invoiceCurrency, 'USD');
      expect(updated.exchangeRate, 50.25);
    });

    test('Multi-currency supplier populates allowed currencies without MULTI', () {
      const multiSupplier = SupplierModel(
        supplierCode: '75001',
        name: 'شركة الاستيراد والتصدير',
        supplierType: 'shared',
        isMultiCurrency: true,
        currency: 'MULTI',
        supportedCurrencies: ['EGP', 'USD', 'EUR'],
        packagingCurrency: 'USD',
      );

      expect(multiSupplier.supportsMultiCurrency, isTrue);
      expect(multiSupplier.supportedCurrencies, containsAll(['EGP', 'USD', 'EUR']));
      expect(multiSupplier.supportedCurrencies.contains('MULTI'), isFalse);
    });

    test('Single-currency supplier falls back to primary currency', () {
      const localSupplier = SupplierModel(
        supplierCode: '70002',
        name: 'مصنع الكرتون',
        supplierType: 'packaging',
        isMultiCurrency: false,
        currency: 'EGP',
        supportedCurrencies: ['EGP'],
      );

      expect(localSupplier.supportsMultiCurrency, isFalse);
      final allowed = localSupplier.supportsMultiCurrency
          ? localSupplier.supportedCurrencies
          : [(localSupplier.currency.isNotEmpty && localSupplier.currency != 'MULTI') ? localSupplier.currency : 'EGP'];
      expect(allowed, ['EGP']);
    });

    test('PurchaseLineData calculates totalPrice and totalPriceEgp with exchange rate', () {
      final line = PurchaseLineData(
        code: 'BOX01',
        name: 'كرتونة تصدير',
        quantity: 100,
        purchasePrice: 2.5, // 2.5 USD
        exchangeRate: 50.0, // 50 EGP per USD
      );

      expect(line.totalPrice, 250.0);
      expect(line.totalPriceEgp, 12500.0);
    });
  });
}
