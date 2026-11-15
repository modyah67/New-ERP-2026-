import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/clearing_agent_model.dart';
import 'package:accounting_system/data/models/shipping_company_model.dart';
import 'package:accounting_system/features/shipping_companies/shipping_company_state.dart';
import 'package:accounting_system/features/clearing_agents/clearing_agent_state.dart';

void main() {
  group('Standardized Clearing & Shipping Models & Currency Tests', () {
    test('ClearingAgentModel parses current_balance and exposes currencySymbol', () {
      final json = {
        'id': '10',
        'code': 'CLR001',
        'name': 'الشركة الدولية للتخليص',
        'phone': '01012345678',
        'broker_type': 'بحري',
        'currency': 'USD',
        'initial_balance': 500.0,
        'current_balance': 1500.0,
        'balance': 1500.0,
      };

      final agent = ClearingAgentModel.fromMap(json);
      expect(agent.id, '10');
      expect(agent.code, 'CLR001');
      expect(agent.name, 'الشركة الدولية للتخليص');
      expect(agent.currency, 'USD');
      expect(agent.currencySymbol, '\$');
      expect(agent.initialBalance, 500.0);
      expect(agent.currentBalance, 1500.0);
      expect(agent.balance, 1500.0);

      final insertMap = agent.toInsertMap();
      expect(insertMap['balance'], 1500.0);
      expect(insertMap['current_balance'], 1500.0);
      expect(insertMap['initial_balance'], 500.0);
      expect(insertMap['currency'], 'USD');
    });

    test('ShippingCompanyModel parses current_balance and exposes currencySymbol', () {
      final json = {
        'id': 20,
        'code': 'SHP001',
        'name': 'ميرسك للملاحة',
        'phone': '01198765432',
        'email': 'maersk@example.com',
        'currency': 'EUR',
        'initial_balance': 1000.0,
        'current_balance': 3500.0,
        'balance': 3500.0,
      };

      final company = ShippingCompanyModel.fromMap(json);
      expect(company.id, 20);
      expect(company.code, 'SHP001');
      expect(company.name, 'ميرسك للملاحة');
      expect(company.currency, 'EUR');
      expect(company.currencySymbol, '€');
      expect(company.initialBalance, 1000.0);
      expect(company.currentBalance, 3500.0);
      expect(company.balance, 3500.0);

      final insertMap = company.toInsertMap();
      expect(insertMap['balance'], 3500.0);
      expect(insertMap['current_balance'], 3500.0);
      expect(insertMap['initial_balance'], 1000.0);
      expect(insertMap['currency'], 'EUR');
    });

    test('Currency symbols mapping for all 4 supported currencies', () {
      final currencies = ['EGP', 'USD', 'EUR', 'GBP'];
      final expectedSymbols = ['ج.م', '\$', '€', '£'];

      for (var i = 0; i < currencies.length; i++) {
        final c = currencies[i];
        final expected = expectedSymbols[i];

        final clr = ClearingAgentModel(
          name: 'Test',
          currency: c,
          createdAt: '',
        );
        expect(clr.currencySymbol, expected);

        final shp = ShippingCompanyModel(
          name: 'Test',
          currency: c,
          createdAt: '',
        );
        expect(shp.currencySymbol, expected);
      }
    });

    test('ShippingCompanyLoaded.fromList aggregates per currency and converts to EGP', () {
      final companies = [
        const ShippingCompanyModel(
          id: 1,
          code: 'S01',
          name: 'Company EGP',
          currency: 'EGP',
          initialBalance: 1000.0,
          balance: 2000.0,
          createdAt: '',
        ),
        const ShippingCompanyModel(
          id: 2,
          code: 'S02',
          name: 'Company USD',
          currency: 'USD',
          initialBalance: 100.0,
          balance: 500.0,
          createdAt: '',
        ),
        const ShippingCompanyModel(
          id: 3,
          code: 'S03',
          name: 'Company EUR',
          currency: 'EUR',
          initialBalance: 50.0,
          balance: 200.0,
          createdAt: '',
        ),
      ];

      final rates = {
        'EGP': 1.0,
        'USD': 50.0,
        'EUR': 55.0,
        'GBP': 65.0,
      };

      final state = ShippingCompanyLoaded.fromList(
        companies: companies,
        rates: rates,
      );

      expect(state.companies.length, 3);
      expect(state.balanceByCurrency.containsKey('EGP'), isTrue);
      expect(state.balanceByCurrency.containsKey('USD'), isTrue);
      expect(state.balanceByCurrency.containsKey('EUR'), isTrue);

      final egpBal = state.balanceByCurrency['EGP']!;
      expect(egpBal.nativeCurrentBalance, 2000.0);
      expect(egpBal.nativeInitialBalance, 1000.0);
      expect(egpBal.egpCurrentBalance, 2000.0);
      expect(egpBal.companyCount, 1);

      final usdBal = state.balanceByCurrency['USD']!;
      expect(usdBal.nativeCurrentBalance, 500.0);
      expect(usdBal.nativeInitialBalance, 100.0);
      expect(usdBal.egpCurrentBalance, 500.0 * 50.0); // 25,000 EGP
      expect(usdBal.companyCount, 1);

      final eurBal = state.balanceByCurrency['EUR']!;
      expect(eurBal.nativeCurrentBalance, 200.0);
      expect(eurBal.nativeInitialBalance, 50.0);
      expect(eurBal.egpCurrentBalance, 200.0 * 55.0); // 11,000 EGP
      expect(eurBal.companyCount, 1);

      // Grand totals converted to EGP: 2000 + 25000 + 11000 = 38,000 EGP
      expect(state.totalCurrentBalanceEgp, 38000.0);
      // Initial: 1000 + (100 * 50) + (50 * 55) = 1000 + 5000 + 2750 = 8750 EGP
      expect(state.totalInitialBalanceEgp, 8750.0);

      // Active currencies canonical order
      final active = state.activeCurrencies;
      expect(active.length, 3);
      expect(active[0].currency, 'EGP');
      expect(active[1].currency, 'USD');
      expect(active[2].currency, 'EUR');
    });

    test('ClearingAgentLoaded.fromList aggregates per currency and converts to EGP', () {
      final agents = [
        const ClearingAgentModel(
          id: '1',
          code: 'C01',
          name: 'Agent Sea',
          brokerType: 'بحري',
          currency: 'EGP',
          initialBalance: 500.0,
          balance: 1500.0,
          createdAt: '',
        ),
        const ClearingAgentModel(
          id: '2',
          code: 'C02',
          name: 'Agent Air',
          brokerType: 'جوي',
          currency: 'GBP',
          initialBalance: 10.0,
          balance: 40.0,
          createdAt: '',
        ),
      ];

      final rates = {
        'EGP': 1.0,
        'USD': 50.0,
        'EUR': 55.0,
        'GBP': 65.0,
      };

      final state = ClearingAgentLoaded.fromList(
        agents: agents,
        rates: rates,
      );

      expect(state.agents.length, 2);
      expect(state.seaCount, 1);
      expect(state.airCount, 1);
      expect(state.totalCurrentBalanceEgp, 1500.0 + (40.0 * 65.0)); // 1500 + 2600 = 4100
      expect(state.totalInitialBalanceEgp, 500.0 + (10.0 * 65.0));  // 500 + 650 = 1150
    });
  });
}
