import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/widgets/password_verification_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Secured Edit Action Integration Verification', () {
    testWidgets('Security dialog prevents unauthorized action flow when wrong password is given', (tester) async {
      bool editProceeded = false;

      Future<void> onEditPressed(BuildContext context) async {
        final verified = await showPasswordVerificationDialog(context);
        if (!verified) return;
        editProceeded = true;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEditPressed(context),
              ),
            ),
          ),
        ),
      );

      // Tap Edit button
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Dialog is displayed
      expect(find.byType(PasswordVerificationDialog), findsOneWidget);

      // Submit invalid password
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      // Edit has NOT proceeded
      expect(editProceeded, isFalse);
      expect(find.text('كلمة المرور غير صحيحة'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(editProceeded, isFalse);
      expect(find.byType(PasswordVerificationDialog), findsNothing);
    });

    testWidgets('Security dialog permits authorized action flow when eslam2026 is entered', (tester) async {
      bool editProceeded = false;

      Future<void> onEditPressed(BuildContext context) async {
        final verified = await showPasswordVerificationDialog(context);
        if (!verified) return;
        editProceeded = true;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEditPressed(context),
              ),
            ),
          ),
        ),
      );

      // Tap Edit button
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Enter administrative password
      await tester.enterText(find.byType(TextField), 'eslam2026');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      // Edit proceeded successfully
      expect(editProceeded, isTrue);
      expect(find.byType(PasswordVerificationDialog), findsNothing);
    });
  });
}
