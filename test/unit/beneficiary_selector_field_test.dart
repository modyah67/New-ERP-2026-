import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/widgets/beneficiary_selector_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BeneficiarySelectorField UI & Categories Tests', () {
    testWidgets('renders all 11 beneficiary categories in dropdown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BeneficiarySelectorField(
                initialBeneficiaryType: 'all_suppliers',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Verify currently selected category label is visible
      expect(find.text('الموردين (عام)'), findsOneWidget);

      // Open the dropdown menu
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Verify all 11 category labels exist in the opened menu
      for (final cat in BeneficiarySelectorField.categories) {
        expect(find.text(cat.label), findsWidgets);
      }
    });

    testWidgets('selecting another category switches state correctly', (tester) async {
      BeneficiarySelection? currentSelection;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BeneficiarySelectorField(
                initialBeneficiaryType: 'all_suppliers',
                onChanged: (sel) {
                  currentSelection = sel;
                },
              ),
            ),
          ),
        ),
      );

      // Open the dropdown
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Tap on 'شركات الشحن'
      await tester.tap(find.text('شركات الشحن').last);
      await tester.pumpAndSettle();

      expect(currentSelection?.beneficiaryType, 'shipping_company');
      expect(currentSelection?.isShippingCompany, isTrue);
      expect(currentSelection?.isSupplier, isFalse);
    });
  });
}
