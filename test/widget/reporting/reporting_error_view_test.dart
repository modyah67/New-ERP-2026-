import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_error_view.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingErrorView', () {
    testWidgets('renders error title', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingErrorView(message: 'Something went wrong'),
      ));
      expect(find.text('خطأ في تحميل البيانات'), findsOneWidget);
    });

    testWidgets('renders error message', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingErrorView(message: 'Connection timeout'),
      ));
      expect(find.text('Connection timeout'), findsOneWidget);
    });

    testWidgets('renders retry button when onRetry is provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingErrorView(
          message: 'Error',
          onRetry: () {},
        ),
      ));
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('does not render retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingErrorView(message: 'Error'),
      ));
      expect(find.text('إعادة المحاولة'), findsNothing);
    });

    testWidgets('calls onRetry when retry button tapped', (tester) async {
      var retryCalled = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingErrorView(
          message: 'Error',
          onRetry: () => retryCalled = true,
        ),
      ));
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retryCalled, isTrue);
    });

    testWidgets('renders error icon', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingErrorView(message: 'Error'),
      ));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders in RTL layout', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        Directionality(
          textDirection: TextDirection.rtl,
          child: const ReportingErrorView(message: 'خطأ'),
        ),
      ));
      expect(find.text('خطأ في تحميل البيانات'), findsOneWidget);
    });
  });
}
