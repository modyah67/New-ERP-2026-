import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_empty_state.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingEmptyState', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingEmptyState(title: 'لا توجد بيانات'),
      ));
      expect(find.text('لا توجد بيانات'), findsOneWidget);
    });

    testWidgets('renders default icon', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingEmptyState(title: 'No data'),
      ));
      expect(find.byIcon(Icons.balance_outlined), findsOneWidget);
    });

    testWidgets('renders custom icon', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingEmptyState(
          title: 'No data',
          icon: Icons.inbox,
        ),
      ));
      expect(find.byIcon(Icons.inbox), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingEmptyState(
          title: 'No data',
          subtitle: 'Add some transactions to get started',
        ),
      ));
      expect(find.text('Add some transactions to get started'), findsOneWidget);
    });

    testWidgets('does not render subtitle when null', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingEmptyState(title: 'No data'),
      ));
      expect(find.byType(Text), findsNWidgets(1));
    });

    testWidgets('renders in RTL layout', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        Directionality(
          textDirection: TextDirection.rtl,
          child: const ReportingEmptyState(title: 'لا توجد بيانات'),
        ),
      ));
      expect(find.text('لا توجد بيانات'), findsOneWidget);
    });

    testWidgets('centers content', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingEmptyState(title: 'Empty'),
      ));
      final centerFinder = find.ancestor(
        of: find.text('Empty'),
        matching: find.byType(Center),
      );
      expect(centerFinder, findsWidgets);
    });
  });
}
