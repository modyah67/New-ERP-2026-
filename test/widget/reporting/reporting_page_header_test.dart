import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_page_header.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingPageHeader', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingPageHeader(title: 'ميزان المراجعة'),
      ));
      expect(find.text('ميزان المراجعة'), findsOneWidget);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingPageHeader(title: 'Test', icon: Icons.account_balance),
      ));
      expect(find.byIcon(Icons.account_balance), findsOneWidget);
    });

    testWidgets('renders count badge when count is provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingPageHeader(
          title: 'Test',
          count: 42,
          countLabel: 'حساب',
        ),
      ));
      expect(find.textContaining('42'), findsOneWidget);
    });

    testWidgets('does not render count badge when count is null', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingPageHeader(title: 'Test'),
      ));
      expect(find.textContaining('حساب'), findsNothing);
    });

    testWidgets('renders action buttons', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingPageHeader(
          title: 'Test',
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
          ],
        ),
      ));
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('renders in LTR layout', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        Directionality(
          textDirection: TextDirection.ltr,
          child: const ReportingPageHeader(title: 'Test Header'),
        ),
      ));
      expect(find.text('Test Header'), findsOneWidget);
    });

    testWidgets('renders in RTL layout', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        Directionality(
          textDirection: TextDirection.rtl,
          child: const ReportingPageHeader(title: 'عنوان التقرير'),
        ),
      ));
      expect(find.text('عنوان التقرير'), findsOneWidget);
    });

    testWidgets('default icon is balance_outlined', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingPageHeader(title: 'Test'),
      ));
      expect(find.byIcon(Icons.balance_outlined), findsOneWidget);
    });
  });
}
