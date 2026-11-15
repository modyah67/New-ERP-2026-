import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/fruit_type_model.dart';
import 'package:accounting_system/features/fruit_types/fruit_type_form_dialog.dart';
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

  group('FruitTypeFormDialog Dual Currency UI Tests', () {
    testWidgets('shows single currency dropdown when purchase mode is not shared', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FruitTypeFormDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should display single standard currency dropdown
      expect(find.text('العملة *'), findsOneWidget);
      expect(find.text('عملة صنف الوزن *'), findsNothing);
      expect(find.text('عملة صنف الكراتين *'), findsNothing);
    });

    testWidgets('dynamically displays two distinct currency dropdowns when shared mode is selected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FruitTypeFormDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open purchase mode dropdown
      final purchaseModeDropdown = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(purchaseModeDropdown);
      await tester.pumpAndSettle();

      // Select 'مشترك (وزن وكراتين)'
      final sharedOption = find.text('مشترك (وزن وكراتين)').last;
      await tester.tap(sharedOption);
      await tester.pumpAndSettle();

      // Standard single currency should now be hidden
      expect(find.text('العملة *'), findsNothing);

      // Both independent currency dropdowns must now be present
      expect(find.text('عملة صنف الوزن *'), findsOneWidget);
      expect(find.text('عملة صنف الكراتين *'), findsOneWidget);
    });
  });

  group('FruitType Model & Dual Currency Attribution Tests', () {
    test('Independent currency attribution for weight and carton records', () {
      const baseName = 'برتقال صيفي';
      const weightCurrency = 'EGP';
      const cartonCurrency = 'USD';

      final weightItem = FruitTypeModel(
        code: '100',
        name: '$baseName - وزن',
        currency: weightCurrency,
        purchaseMode: 'weight',
      );

      final cartonItem = FruitTypeModel(
        code: '101',
        name: '$baseName - كراتين',
        currency: cartonCurrency,
        purchaseMode: 'carton',
      );

      expect(weightItem.name, 'برتقال صيفي - وزن');
      expect(weightItem.currency, 'EGP');
      expect(weightItem.purchaseMode, 'weight');

      expect(cartonItem.name, 'برتقال صيفي - كراتين');
      expect(cartonItem.currency, 'USD');
      expect(cartonItem.purchaseMode, 'carton');
    });
  });
}
