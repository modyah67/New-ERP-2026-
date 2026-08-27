import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_summary_cards.dart';
import 'package:accounting_system/reporting/models/reporting_models.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingSummaryCards', () {
    final metrics = [
      const MetricData(
        title: 'إجمالي المدين',
        value: '500,000',
        icon: Icons.trending_up,
        color: Colors.green,
      ),
      const MetricData(
        title: 'إجمالي الدائن',
        value: '480,000',
        icon: Icons.trending_down,
        color: Colors.red,
      ),
      const MetricData(
        title: 'صافي الربح',
        value: '20,000',
        icon: Icons.account_balance,
        color: Colors.blue,
      ),
    ];

    testWidgets('renders all metric cards', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingSummaryCards(metrics: metrics),
      ));
      expect(find.text('إجمالي المدين'), findsOneWidget);
      expect(find.text('إجمالي الدائن'), findsOneWidget);
      expect(find.text('صافي الربح'), findsOneWidget);
    });

    testWidgets('renders metric values', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingSummaryCards(metrics: metrics),
      ));
      expect(find.text('500,000'), findsOneWidget);
      expect(find.text('480,000'), findsOneWidget);
      expect(find.text('20,000'), findsOneWidget);
    });

    testWidgets('renders metric icons', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingSummaryCards(metrics: metrics),
      ));
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
      expect(find.byIcon(Icons.account_balance), findsOneWidget);
    });

    testWidgets('renders empty state when no metrics', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingSummaryCards(metrics: []),
      ));
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('renders single metric card', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        const ReportingSummaryCards(metrics: [
          MetricData(
            title: 'Test',
            value: '100',
            icon: Icons.star,
            color: Colors.amber,
          ),
        ]),
      ));
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('renders horizontally scrollable list', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingSummaryCards(metrics: metrics),
      ));
      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.scrollDirection, Axis.horizontal);
    });

    testWidgets('renders in RTL layout', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        Directionality(
          textDirection: TextDirection.rtl,
          child: ReportingSummaryCards(metrics: metrics),
        ),
      ));
      expect(find.text('إجمالي المدين'), findsOneWidget);
    });
  });
}
