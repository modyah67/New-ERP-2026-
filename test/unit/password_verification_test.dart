import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/widgets/password_verification_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Password Verification Dialog & Helper Tests', () {
    testWidgets('renders dialog elements correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordVerificationDialog(),
          ),
        ),
      );

      expect(find.text('تأكيد كلمة المرور للمتابعة'), findsOneWidget);
      expect(find.text('يرجى إدخال كلمة المرور لتعديل البيانات'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('تأكيد'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.password_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('toggles password visibility with eye icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordVerificationDialog(),
          ),
        ),
      );

      final textFieldFinder = find.byType(TextField);
      TextField textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.obscureText, isTrue);

      // Tap visibility toggle icon
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap again to obscure
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.obscureText, isTrue);
    });

    testWidgets('shows validation error when submitting empty password', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordVerificationDialog(),
          ),
        ),
      );

      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      expect(find.text('يرجى إدخال كلمة المرور'), findsOneWidget);
    });

    testWidgets('shows validation error on incorrect password and does not close', (WidgetTester tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showPasswordVerificationDialog(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter wrong password
      await tester.enterText(find.byType(TextField), 'wrongpassword123');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      // Check error text is visible
      expect(find.text('كلمة المرور غير صحيحة'), findsOneWidget);
      // Dialog must still be open
      expect(find.byType(PasswordVerificationDialog), findsOneWidget);
      expect(dialogResult, isNull);
    });

    testWidgets('returns true on correct administrative password eslam2026', (WidgetTester tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showPasswordVerificationDialog(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter correct password
      await tester.enterText(find.byType(TextField), 'eslam2026');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      // Dialog is closed and result is true
      expect(find.byType(PasswordVerificationDialog), findsNothing);
      expect(dialogResult, isTrue);
    });

    testWidgets('returns false when cancelled', (WidgetTester tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showPasswordVerificationDialog(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(find.byType(PasswordVerificationDialog), findsNothing);
      expect(dialogResult, isFalse);
    });
  });
}
