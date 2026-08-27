import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_validation_panel.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

void main() {
  Widget wrapWide(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1400,
          height: 200,
          child: child,
        ),
      ),
    );
  }

  group('ReportingValidationPanel', () {
    testWidgets('shows balanced status when isBalanced is true', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(wrapWide(
        const ReportingValidationPanel(
          isBalanced: true,
          totalDebit: 100000,
          totalCredit: 100000,
          difference: 0,
        ),
      ));
      expect(find.text('متوازن ✓'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('shows unbalanced status when isBalanced is false', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(wrapWide(
        const ReportingValidationPanel(
          isBalanced: false,
          totalDebit: 100000,
          totalCredit: 95000,
          difference: 5000,
        ),
      ));
      expect(find.text('غير متوازن ⚠'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    });

    testWidgets('displays total debit and credit', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(wrapWide(
        const ReportingValidationPanel(
          isBalanced: true,
          totalDebit: 100000,
          totalCredit: 100000,
          difference: 0,
        ),
      ));
      expect(find.text('إجمالي المدين'), findsOneWidget);
      expect(find.text('إجمالي الدائن'), findsOneWidget);
    });

    testWidgets('displays difference', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(wrapWide(
        const ReportingValidationPanel(
          isBalanced: false,
          totalDebit: 100000,
          totalCredit: 95000,
          difference: 5000,
        ),
      ));
      expect(find.text('الفرق'), findsOneWidget);
    });

    testWidgets('shows custom labels', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(wrapWide(
        const ReportingValidationPanel(
          isBalanced: true,
          totalDebit: 100000,
          totalCredit: 100000,
          difference: 0,
          debitLabel: 'Total DR',
          creditLabel: 'Total CR',
          differenceLabel: 'Diff',
        ),
      ));
      expect(find.text('Total DR'), findsOneWidget);
      expect(find.text('Total CR'), findsOneWidget);
      expect(find.text('Diff'), findsOneWidget);
    });

    testWidgets('expands validation issues when tapped', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vr = ValidationResult.failure([
        const ValidationIssue(
          code: 'TB_UNBALANCED',
          message: 'Trial balance not balanced',
          messageAr: 'الميزانية التجريبية غير متوازنة',
          severity: ValidationSeverity.error,
        ),
      ]);

      await tester.pumpWidget(wrapWide(
        ReportingValidationPanel(
          isBalanced: false,
          totalDebit: 100000,
          totalCredit: 95000,
          difference: 5000,
          validationResult: vr,
        ),
      ));
      await tester.pumpAndSettle();

      // Initially collapsed
      expect(find.text('الميزانية التجريبية غير متوازنة'), findsNothing);

      // Tap to expand
      await tester.tap(find.text('1 أخطاء'));
      await tester.pumpAndSettle();

      // Now the issue message should be visible
      expect(find.text('الميزانية التجريبية غير متوازنة'), findsOneWidget);
    });

    testWidgets('collapses when tapped again', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vr = ValidationResult.failure([
        const ValidationIssue(
          code: 'TB_UNBALANCED',
          message: 'Trial balance not balanced',
          messageAr: 'الميزانية التجريبية غير متوازنة',
          severity: ValidationSeverity.error,
        ),
      ]);

      await tester.pumpWidget(wrapWide(
        ReportingValidationPanel(
          isBalanced: false,
          totalDebit: 100000,
          totalCredit: 95000,
          difference: 5000,
          validationResult: vr,
        ),
      ));
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(find.text('1 أخطاء'));
      await tester.pumpAndSettle();
      expect(find.text('الميزانية التجريبية غير متوازنة'), findsOneWidget);

      // Collapse
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pumpAndSettle();
      expect(find.text('الميزانية التجريبية غير متوازنة'), findsNothing);
    });

    testWidgets('shows warning count', (tester) async {
      tester.view.physicalSize = const Size(1400 * 3, 200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vr = ValidationResult.failure([
        const ValidationIssue(
          code: 'TB_EMPTY',
          message: 'Trial balance has no rows',
          messageAr: 'الميزانية التجريبية فارغة',
          severity: ValidationSeverity.warning,
        ),
      ]);

      await tester.pumpWidget(wrapWide(
        ReportingValidationPanel(
          isBalanced: true,
          totalDebit: 0,
          totalCredit: 0,
          difference: 0,
          validationResult: vr,
        ),
      ));
      expect(find.text('1 تحذيرات'), findsOneWidget);
    });
  });
}
