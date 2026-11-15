import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/clearing_agent_model.dart';
import 'package:accounting_system/features/clearing_agents/clearance_agents_pdf_service.dart';
import 'package:accounting_system/features/clearing_agents/clearing_agent_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClearanceAgentsPdfService Landscape & Multi-Currency Tests', () {
    final sampleAgents = [
      const ClearingAgentModel(
        id: 'ca-1',
        code: 'CLR0001',
        name: 'شركة الإسكندرية للتخليص والخدمات البحرية',
        phone: '01011223344',
        brokerType: 'بحري',
        currency: 'EGP',
        initialBalance: 25000.0,
        balance: 65000.0,
        createdAt: '2026-01-01',
      ),
      const ClearingAgentModel(
        id: 'ca-2',
        code: 'CLR0002',
        name: 'مؤسسة مطار القاهرة لخدمات الشحن الجوي',
        phone: '01122334455',
        brokerType: 'جوي',
        currency: 'USD',
        initialBalance: 1500.0,
        balance: 3200.0,
        createdAt: '2026-01-01',
      ),
      const ClearingAgentModel(
        id: 'ca-3',
        code: 'CLR0003',
        name: 'مكتب السويس اللوجستي للتخليص',
        phone: '01233445566',
        brokerType: 'بحري',
        currency: 'EUR',
        initialBalance: 1000.0,
        balance: -500.0,
        createdAt: '2026-01-01',
      ),
      const ClearingAgentModel(
        id: 'ca-4',
        code: 'CLR0004',
        name: 'أير ترانزيت للشحن السريع',
        phone: '01544556677',
        brokerType: 'جوي',
        currency: 'GBP',
        initialBalance: 800.0,
        balance: 2100.0,
        createdAt: '2026-01-01',
      ),
    ];

    test('ClearingAgentLoaded.fromList computes Sea/Air counts and per-currency balances correctly', () {
      final loaded = ClearingAgentLoaded.fromList(
        agents: sampleAgents,
        rates: const {
          'EGP': 1.0,
          'USD': 50.0,
          'EUR': 55.0,
          'GBP': 65.0,
        },
      );

      expect(loaded.seaCount, equals(2));
      expect(loaded.airCount, equals(2));
      expect(loaded.balanceByCurrency.containsKey('EGP'), isTrue);
      expect(loaded.balanceByCurrency.containsKey('USD'), isTrue);
      expect(loaded.balanceByCurrency.containsKey('EUR'), isTrue);
      expect(loaded.balanceByCurrency.containsKey('GBP'), isTrue);

      // Verify native current balances
      expect(loaded.balanceByCurrency['EGP']!.nativeCurrentBalance, equals(65000.0));
      expect(loaded.balanceByCurrency['USD']!.nativeCurrentBalance, equals(3200.0));
      expect(loaded.balanceByCurrency['EUR']!.nativeCurrentBalance, equals(-500.0));
      expect(loaded.balanceByCurrency['GBP']!.nativeCurrentBalance, equals(2100.0));

      // Verify converted EGP total
      // 65,000 + (3,200 * 50 = 160,000) + (-500 * 55 = -27,500) + (2,100 * 65 = 136,500) = 334,000
      expect(loaded.totalCurrentBalanceEgp, equals(334000.0));
    });

    test('generatePdf compiles and returns non-empty landscape PDF bytes for clearance agents', () async {
      final pdfBytes = await ClearanceAgentsPdfService.generatePdf(
        agents: sampleAgents,
        companyName: 'مزارع فروتي فارمز',
        exchangeRates: const {
          'EGP': 1.0,
          'USD': 50.0,
          'EUR': 55.0,
          'GBP': 65.0,
        },
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(2000));
      // PDF documents start with %PDF header
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('generatePdf works gracefully with empty clearing agents list without crashing', () async {
      final pdfBytes = await ClearanceAgentsPdfService.generatePdf(
        agents: [],
        companyName: 'مزارع فروتي فارمز',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });
  });
}
