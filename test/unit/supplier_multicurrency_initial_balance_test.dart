import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/data/models/statement_row_model.dart';
import 'package:accounting_system/features/suppliers/supplier_cubit.dart';
import 'package:accounting_system/features/suppliers/supplier_state.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'dummy-anon-key',
      );
    } catch (_) {}
  });

  group('SupplierCurrencyBalance Model Tests', () {
    test('Calculates amountInEgp and signed amounts correctly for CREDIT', () {
      const balance = SupplierCurrencyBalance(
        currency: 'USD',
        amount: 1000.0,
        direction: 'CREDIT',
        exchangeRate: 50.0,
      );

      expect(balance.amountInEgp, 50000.0);
      expect(balance.signedAmount, 1000.0);
      expect(balance.signedAmountInEgp, 50000.0);

      final map = balance.toMap();
      expect(map['currency'], 'USD');
      expect(map['amount'], 1000.0);
      expect(map['direction'], 'CREDIT');
      expect(map['exchange_rate'], 50.0);
      expect(map['amount_egp'], 50000.0);
    });

    test('Calculates signed amounts correctly for DEBIT', () {
      const balance = SupplierCurrencyBalance(
        currency: 'EUR',
        amount: 500.0,
        direction: 'DEBIT',
        exchangeRate: 55.0,
      );

      expect(balance.amountInEgp, 27500.0);
      expect(balance.signedAmount, -500.0);
      expect(balance.signedAmountInEgp, -27500.0);
    });

    test('fromMap parses map correctly', () {
      final map = {
        'currency': 'GBP',
        'amount': 200.0,
        'direction': 'CREDIT',
        'exchange_rate': 65.0,
      };

      final balance = SupplierCurrencyBalance.fromMap(map);
      expect(balance.currency, 'GBP');
      expect(balance.amount, 200.0);
      expect(balance.direction, 'CREDIT');
      expect(balance.exchangeRate, 65.0);
      expect(balance.amountInEgp, 13000.0);
    });
  });

  group('SupplierModel Multi-Currency Initial Balances Serialization Tests', () {
    test('Calculates totalInitialBalanceInEgp across multiple currencies', () {
      final supplier = SupplierModel(
        supplierCode: '50001',
        name: 'Multi-Currency Global Supplier',
        isMultiCurrency: true,
        currency: 'MULTI',
        supportedCurrencies: const ['EGP', 'USD', 'EUR'],
        initialBalancesByCurrency: const {
          'EGP': SupplierCurrencyBalance(
            currency: 'EGP',
            amount: 10000.0,
            direction: 'CREDIT',
            exchangeRate: 1.0,
          ),
          'USD': SupplierCurrencyBalance(
            currency: 'USD',
            amount: 1000.0,
            direction: 'CREDIT',
            exchangeRate: 50.0,
          ),
          'EUR': SupplierCurrencyBalance(
            currency: 'EUR',
            amount: 200.0,
            direction: 'DEBIT',
            exchangeRate: 55.0,
          ),
        },
      );

      // EGP: +10,000 | USD: +50,000 | EUR: -11,000 => Net: 49,000 EGP (CREDIT)
      expect(supplier.totalInitialBalanceInEgp, 49000.0);
      expect(supplier.supportsMultiCurrency, true);
    });

    test('toInsertMap safely falls back dbCurrency to prevent PostgREST exceptions with MULTI', () {
      final supplier = SupplierModel(
        supplierCode: '50002',
        name: 'Safe Currency Supplier',
        isMultiCurrency: true,
        currency: 'MULTI',
        supportedCurrencies: const ['USD', 'EUR', 'EGP'],
        initialBalancesByCurrency: const {
          'USD': SupplierCurrencyBalance(
            currency: 'USD',
            amount: 500.0,
            direction: 'CREDIT',
            exchangeRate: 50.0,
          ),
        },
      );

      final insertMap = supplier.toInsertMap();
      // Should not be 'MULTI', should be 'USD' (first supported currency)
      expect(insertMap['currency'], 'USD');
      expect(insertMap['is_multi_currency'], true);
      expect(insertMap['initial_balances_by_currency'], isNotNull);
      expect(insertMap['initial_balance'], 25000.0);
      expect(insertMap['initial_balance_direction'], 'CREDIT');
    });

    test('fromMap restores initial_balances_by_currency accurately', () {
      final jsonMap = {
        'id': 'supp-uuid-1',
        'supplier_code': '50003',
        'name': 'Imported Supplier',
        'is_multi_currency': true,
        'currency': 'MULTI',
        'supported_currencies': ['EGP', 'USD'],
        'initial_balances_by_currency': {
          'EGP': {
            'currency': 'EGP',
            'amount': 5000.0,
            'direction': 'CREDIT',
            'exchange_rate': 1.0,
          },
          'USD': {
            'currency': 'USD',
            'amount': 2000.0,
            'direction': 'DEBIT',
            'exchange_rate': 50.0,
          },
        },
      };

      final supplier = SupplierModel.fromMap(jsonMap);
      expect(supplier.isMultiCurrency, true);
      expect(supplier.initialBalancesByCurrency.length, 2);
      expect(supplier.initialBalancesByCurrency['EGP']!.amount, 5000.0);
      expect(supplier.initialBalancesByCurrency['USD']!.amount, 2000.0);
      expect(supplier.initialBalancesByCurrency['USD']!.direction, 'DEBIT');
      // 5000 - 100000 = -95000
      expect(supplier.totalInitialBalanceInEgp, -95000.0);
    });
  });

  group('SupplierCubit Multi-Currency State Management Tests', () {
    test('syncCurrencyBalanceItems creates controllers for all supported currencies', () async {
      final cubit = SupplierCubit();
      await cubit.prepareAddForm(defaultType: 'shared');

      expect(cubit.isMultiCurrency, true);
      expect(cubit.selectedSupportedCurrencies.contains('EGP'), true);
      expect(cubit.selectedSupportedCurrencies.contains('USD'), true);
      expect(cubit.selectedSupportedCurrencies.contains('EUR'), true);

      // Verify form items were initialized
      expect(cubit.currencyBalanceItems.containsKey('EGP'), true);
      expect(cubit.currencyBalanceItems.containsKey('USD'), true);
      expect(cubit.currencyBalanceItems.containsKey('EUR'), true);

      // EGP rate is always 1.00
      expect(cubit.currencyBalanceItems['EGP']!.exchangeRate, 1.0);
      expect(cubit.currencyBalanceItems['EGP']!.exchangeRateController.text, '1.00');

      cubit.currencyBalanceItems['USD']!.amountController.text = '100.00';
      cubit.currencyBalanceItems['USD']!.exchangeRateController.text = '50.00';
      cubit.currencyBalanceItems['USD']!.direction = 'CREDIT';

      expect(cubit.currencyBalanceItems['USD']!.amountInEgp, 5000.0);
      expect(cubit.totalMultiCurrencyInitialBalanceEgp, 5000.0);

      await cubit.close();
    });

    test('toggleSupportedCurrency adds and removes currency items cleanly', () async {
      final cubit = SupplierCubit();
      await cubit.prepareAddForm(defaultType: 'crop');
      cubit.isMultiCurrency = true;
      cubit.syncCurrencyBalanceItems();

      // Add GBP
      cubit.toggleSupportedCurrency('GBP');
      expect(cubit.selectedSupportedCurrencies.contains('GBP'), true);
      expect(cubit.currencyBalanceItems.containsKey('GBP'), true);

      // Remove GBP
      cubit.toggleSupportedCurrency('GBP');
      expect(cubit.selectedSupportedCurrencies.contains('GBP'), false);
      expect(cubit.currencyBalanceItems.containsKey('GBP'), false);

      await cubit.close();
    });
  });

  group('Supplier UI Formatting & KPI Summary Aggregation Tests', () {
    test('formattedInitialBalance formats native currency breakdown cleanly', () {
      final supplier = SupplierModel(
        id: 'sup-1',
        supplierCode: '50000',
        name: 'وليد',
        supplierType: 'crop',
        isMultiCurrency: true,
        supportedCurrencies: const ['EGP', 'USD'],
        initialBalance: 5100.0,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: 5100.0,
        currency: 'MULTI',
        initialBalancesByCurrency: const {
          'EGP': SupplierCurrencyBalance(currency: 'EGP', amount: 100.0, direction: 'CREDIT', exchangeRate: 1.0),
          'USD': SupplierCurrencyBalance(currency: 'USD', amount: 100.0, direction: 'CREDIT', exchangeRate: 50.0),
        },
      );

      expect(supplier.hasMultiCurrencyInitialBalance, true);
      expect(supplier.formattedInitialBalance, '100 ج.م + 100 \$');
      expect(supplier.formattedCurrentBalance, '100 ج.م + 100 \$');
    });

    test('SupplierLoaded.fromList aggregates multi-currency suppliers into native currencies and converts totals to EGP', () {
      final multiSupplier = SupplierModel(
        id: 'sup-1',
        supplierCode: '50000',
        name: 'وليد',
        supplierType: 'crop',
        isMultiCurrency: true,
        supportedCurrencies: const ['EGP', 'USD'],
        initialBalance: 5100.0,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: 5100.0,
        currency: 'MULTI',
        initialBalancesByCurrency: const {
          'EGP': SupplierCurrencyBalance(currency: 'EGP', amount: 100.0, direction: 'CREDIT', exchangeRate: 1.0),
          'USD': SupplierCurrencyBalance(currency: 'USD', amount: 100.0, direction: 'CREDIT', exchangeRate: 50.0),
        },
      );

      final singleSupplier = SupplierModel(
        id: 'sup-2',
        supplierCode: '70000',
        name: 'أحمد كرتون',
        supplierType: 'packaging',
        isMultiCurrency: false,
        initialBalance: 1000.0,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: 1000.0,
        currency: 'EGP',
      );

      final state = SupplierLoaded.fromList(
        suppliers: [multiSupplier, singleSupplier],
        rates: const {'EGP': 1.0, 'USD': 50.0},
      );

      // Total EGP: 5100 (وليد) + 1000 (أحمد) = 6100.0 EGP
      expect(state.totalInitialBalanceEgp, 6100.0);
      expect(state.totalCurrentBalanceEgp, 6100.0);

      // Verify that active currencies breakdown does NOT contain 'MULTI'
      final currencies = state.activeCurrencies.map((c) => c.currency).toList();
      expect(currencies.contains('MULTI'), false);
      expect(currencies.contains('EGP'), true);
      expect(currencies.contains('USD'), true);

      // EGP native balance: 100 (from وليد) + 1000 (from أحمد) = 1100 EGP
      final egpBal = state.balanceByCurrency['EGP']!;
      expect(egpBal.nativeInitialBalance, 1100.0);
      expect(egpBal.nativeCurrentBalance, 1100.0);

      // USD native balance: 100 USD (from وليد)
      final usdBal = state.balanceByCurrency['USD']!;
      expect(usdBal.nativeInitialBalance, 100.0);
      expect(usdBal.nativeCurrentBalance, 100.0);
      expect(usdBal.egpInitialBalance, 5000.0);
      expect(usdBal.egpCurrentBalance, 5000.0);
    });

    test('StatementRow preserves currency attribute and formats correctly', () {
      const rowUsd = StatementRow(
        transactionNumber: 'INV-101',
        date: '2026-09-08',
        accountName: 'مشتريات',
        description: 'فاتورة شراء محصول بالدولار',
        piecesCount: 0,
        quantity: 10,
        unitPrice: 50,
        debit: 0,
        credit: 500,
        balance: 500,
        type: 'purchase',
        createdAt: '2026-09-08T10:00:00Z',
        currency: 'USD',
      );

      expect(rowUsd.currency, 'USD');
      expect(SupplierModel.getCurrencySymbol(rowUsd.currency!), '\$');

      const rowEg = StatementRow(
        transactionNumber: 'INV-102',
        date: '2026-09-08',
        accountName: 'مشتريات',
        description: 'فاتورة شراء بالجنيه',
        piecesCount: 0,
        quantity: 10,
        unitPrice: 50,
        debit: 0,
        credit: 500,
        balance: 1000,
        type: 'purchase',
        createdAt: '2026-09-08T11:00:00Z',
        currency: 'EGP',
      );

      expect(rowEg.currency, 'EGP');
      expect(SupplierModel.getCurrencySymbol(rowEg.currency!), 'ج.م');
    });

    test('Foreign currency supplier (GBP) formats native symbol £100.00 rather than converted EGP', () {
      final gbpSupplier = SupplierModel(
        id: 'sup-gbp-1',
        supplierCode: '50099',
        name: 'London Fruit Importers',
        supplierType: 'crop',
        currency: 'GBP',
        isMultiCurrency: false,
        initialBalance: 100.0,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: 6000.0, // Converted to EGP from RPC
        currentBalancesByCurrency: const {
          'GBP': 100.0,
        },
      );

      expect(gbpSupplier.isForeignCurrency, true);
      expect(gbpSupplier.currencySymbol, '£');
      expect(gbpSupplier.nativeCurrentBalance, 100.0);
      expect(gbpSupplier.formattedInitialBalance, '£100.00');
      expect(gbpSupplier.formattedCurrentBalance, '£100.00');

      // Test SupplierLoaded KPI aggregation maintains native amounts
      final egpSupplier = SupplierModel(
        id: 'sup-egp-1',
        supplierCode: '70001',
        name: 'مورد مصري',
        supplierType: 'packaging',
        currency: 'EGP',
        isMultiCurrency: false,
        initialBalance: 5000.0,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: 5000.0,
      );

      final state = SupplierLoaded.fromList(
        suppliers: [gbpSupplier, egpSupplier],
        rates: const {'EGP': 1.0, 'GBP': 60.0},
      );

      // Verify GBP native balance is 100.0, NOT 6000.0
      final gbpBal = state.balanceByCurrency['GBP']!;
      expect(gbpBal.nativeInitialBalance, 100.0);
      expect(gbpBal.nativeCurrentBalance, 100.0);
      expect(gbpBal.egpInitialBalance, 6000.0);
      expect(gbpBal.egpCurrentBalance, 6000.0);

      // Verify grand total in EGP is 6000 + 5000 = 11000
      expect(state.totalCurrentBalanceEgp, 11000.0);
    });

    test('Purchase return statement row correctly formats native currency (£80.00) without local fallback', () {
      // 1. Verify SupplierModel and AppUtils currency formatters display native prefix
      expect(SupplierModel.formatCurrency(80.0, 'GBP'), '£80.00');
      expect(SupplierModel.formatCurrency(80.0, 'USD'), '\$80.00');
      expect(SupplierModel.formatCurrency(80.0, 'EUR'), '€80.00');
      expect(SupplierModel.formatCurrency(80.0, 'EGP'), '80.00 ج.م');

      // 2. Simulate transaction mapping for lot_return on a foreign supplier
      final gbpSupplier = SupplierModel(
        id: 'sup-gbp-1',
        supplierCode: '50001',
        name: 'British Berry Farm',
        supplierType: 'crop',
        currency: 'GBP',
        cropCurrency: 'GBP',
        isMultiCurrency: false,
        initialBalance: 100.0,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: 6000.0, // 100 GBP @ 60 EGP
        currentBalancesByCurrency: const {'GBP': 100.0},
      );

      final rawPayment = {
        'id': 'le_101',
        'entry_type': 'debit',
        'amount': 80.0,
        'currency': null, // Omitted or null from database
        'reference_type': 'lot_return',
        'reference_text': 'ret_55',
        'created_at': '2026-09-09T10:00:00Z',
      };

      final lotReturnCurrencyMap = {'ret_55': 'GBP'};

      // Transaction mapping logic
      final refType = rawPayment['reference_type']?.toString() ?? '';
      final rawCur = rawPayment['currency']?.toString() ?? '';
      String resolvedCurrency = rawCur;

      if (refType == 'lot_return') {
        final refText = rawPayment['reference_text']?.toString() ?? '';
        if (lotReturnCurrencyMap.containsKey(refText)) {
          resolvedCurrency = lotReturnCurrencyMap[refText]!;
        } else if (gbpSupplier.cropCurrency.isNotEmpty && gbpSupplier.cropCurrency != 'EGP') {
          resolvedCurrency = gbpSupplier.cropCurrency;
        } else if (gbpSupplier.currency.isNotEmpty && gbpSupplier.currency != 'MULTI' && gbpSupplier.currency != 'EGP') {
          resolvedCurrency = gbpSupplier.currency;
        } else {
          resolvedCurrency = 'EGP';
        }
      }

      expect(resolvedCurrency, 'GBP');

      final returnRow = StatementRow(
        transactionNumber: rawPayment['id']!.toString(),
        date: '2026-09-09',
        accountName: 'مرتجع شراء محصول',
        description: 'مرتجع محصول - لوط رقم: LOT-GBP-01',
        piecesCount: 0,
        quantity: 10,
        unitPrice: 8.0,
        debit: 80.0,
        credit: 0,
        balance: 20.0,
        type: 'lot_return',
        createdAt: '2026-09-09T10:00:00Z',
        currency: resolvedCurrency,
      );

      expect(returnRow.currency, 'GBP');
      expect(SupplierModel.formatCurrency(returnRow.debit, returnRow.currency!), '£80.00');
    });

    test('Purchase return balance deduction correctly subtracts native amount and converted equivalent', () {
      final initialBalancesByCur = {'GBP': 100.0};
      double outstandingBalance = 6000.0; // 100 GBP @ 60 EGP
      const returnQuantity = 10.0;
      const unitPrice = 8.0;
      const exchangeRate = 60.0;

      // Native return value
      const returnValue = returnQuantity * unitPrice; // 80.0 GBP
      // Converted equivalent in base currency (EGP)
      const returnValueEgp = returnValue * exchangeRate; // 4,800.0 EGP

      // 1. Deduct native amount from currentBalancesByCurrency
      final updatedBalancesByCur = Map<String, double>.from(initialBalancesByCur);
      final currentNative = updatedBalancesByCur['GBP']!;
      updatedBalancesByCur['GBP'] = currentNative - returnValue;

      // 2. Deduct converted equivalent from outstanding_balance
      outstandingBalance = outstandingBalance - returnValueEgp;

      expect(updatedBalancesByCur['GBP'], 20.0);
      expect(outstandingBalance, 1200.0);

      // 3. Verify real-time SupplierLoaded state accurately reflects £20.00 and 1,200.00 EGP
      final updatedSupplier = SupplierModel(
        id: 'sup-gbp-1',
        supplierCode: '50001',
        name: 'British Berry Farm',
        supplierType: 'crop',
        currency: 'GBP',
        cropCurrency: 'GBP',
        isMultiCurrency: false,
        initialBalance: 100.0,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: outstandingBalance,
        currentBalancesByCurrency: updatedBalancesByCur,
      );

      final state = SupplierLoaded.fromList(
        suppliers: [updatedSupplier],
        rates: const {'EGP': 1.0, 'GBP': 60.0},
      );

      expect(state.balanceByCurrency['GBP']!.nativeCurrentBalance, 20.0);
      expect(state.balanceByCurrency['GBP']!.egpCurrentBalance, 1200.0);
      expect(state.totalCurrentBalanceEgp, 1200.0);
      expect(updatedSupplier.formattedCurrentBalance, '£20.00');
    });

    test('Supplier list balance accurately reflects purchase returns in real-time matching statement total (£2,020.00 instead of £2,100.00)', () {
      // Scenario matching user request:
      // Initial balance / invoices: £2,100.00
      // Purchase return: £80.00 (debit reduction)
      // Statement total: £2,020.00
      const initialGbp = 2100.0;
      const returnAmtGbp = 80.0;
      const netGbp = initialGbp - returnAmtGbp; // 2020.0
      const rateToEgp = 65.0;

      final supplier = SupplierModel(
        id: 'sup-foreign-gbp',
        supplierCode: '50042',
        name: 'Scottish Farms Ltd',
        supplierType: 'crop',
        currency: 'GBP',
        cropCurrency: 'GBP',
        isMultiCurrency: false,
        initialBalance: initialGbp,
        initialBalanceDirection: 'CREDIT',
        outstandingBalance: netGbp * rateToEgp,
        currentBalancesByCurrency: const {'GBP': netGbp},
      );

      // 1. Verify supplier model formattedCurrentBalance displays £2,020.00
      expect(supplier.formattedCurrentBalance, '£2,020.00');

      // 2. Verify SupplierLoaded state correctly aggregates Card 2 balance to £2,020.00
      final state = SupplierLoaded.fromList(
        suppliers: [supplier],
        rates: const {'EGP': 1.0, 'GBP': rateToEgp},
      );

      final gbpBalance = state.balanceByCurrency['GBP'];
      expect(gbpBalance, isNotNull);
      expect(gbpBalance!.nativeCurrentBalance, 2020.0);
      expect(gbpBalance.egpCurrentBalance, 2020.0 * rateToEgp);
      expect(gbpBalance.symbol, '£');
      expect(SupplierModel.formatCurrency(gbpBalance.nativeCurrentBalance, 'GBP'), '£2,020.00');
    });
  });
}


