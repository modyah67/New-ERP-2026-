import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_scaffold.dart';
import 'package:accounting_system/reporting/widgets/reporting_data_grid.dart';
import 'package:accounting_system/reporting/widgets/reporting_summary_cards.dart';
import 'package:accounting_system/reporting/widgets/reporting_toolbar.dart';
import 'package:accounting_system/reporting/widgets/reporting_page_header.dart';
import 'package:accounting_system/reporting/models/reporting_models.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingScaffold', () {
    final columns = [
      const ReportColumn(key: 'code', label: 'Code', labelAr: 'الكود', fixedWidth: 100),
      const ReportColumn(key: 'name', label: 'Name', labelAr: 'الاسم', flex: 2),
    ];

    final rows = [
      const ReportingRowData(
        id: '1',
        cells: {'code': '1000', 'name': 'Cash'},
      ),
    ];

    String defaultCellRenderer(ReportingRowData row, ReportColumn column) {
      return row.cells[column.key]?.toString() ?? '';
    }

    testWidgets('renders header title', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'ميزان المراجعة',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          columns: columns,
          rows: rows,
        ),
      ));
      expect(find.text('ميزان المراجعة'), findsOneWidget);
    });

    testWidgets('renders refresh button', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
        ),
      ));
      expect(find.text('تحديث'), findsOneWidget);
    });

    testWidgets('renders data grid', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          columns: columns,
          rows: rows,
        ),
      ));
      expect(find.byType(ReportingDataGrid), findsOneWidget);
    });

    testWidgets('renders summary cards when metrics provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          metrics: const [
            MetricData(
              title: 'Total',
              value: '1000',
              icon: Icons.star,
              color: Colors.blue,
            ),
          ],
        ),
      ));
      expect(find.byType(ReportingSummaryCards), findsOneWidget);
    });

    testWidgets('does not render summary cards when metrics is null', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
        ),
      ));
      expect(find.byType(ReportingSummaryCards), findsNothing);
    });

    testWidgets('renders validation panel when all validation props provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          isBalanced: true,
          totalDebit: 100000,
          totalCredit: 100000,
          difference: 0,
        ),
      ));
      expect(find.text('متوازن ✓'), findsOneWidget);
    });

    testWidgets('shows loading overlay when refreshing', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          isRefreshing: true,
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides loading overlay when not refreshing', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          isRefreshing: false,
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders empty state when rows empty and emptyState provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          rows: [],
          emptyState: const Center(child: Text('No data available')),
        ),
      ));
      expect(find.text('No data available'), findsOneWidget);
      expect(find.byType(ReportingDataGrid), findsNothing);
    });

    testWidgets('renders filter bar when provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          filterBar: const SizedBox(height: 50, child: Text('Filter Bar')),
        ),
      ));
      expect(find.text('Filter Bar'), findsOneWidget);
    });

    testWidgets('calls onRefresh when toolbar refresh tapped', (tester) async {
      var refreshCalled = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () => refreshCalled = true,
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
        ),
      ));
      await tester.tap(find.text('تحديث'));
      expect(refreshCalled, isTrue);
    });

    testWidgets('renders in RTL layout', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        Directionality(
          textDirection: TextDirection.rtl,
          child: ReportingScaffold(
            headerTitle: 'تقرير مالي',
            onRefresh: () {},
            onFullscreen: () {},
            cellRenderer: defaultCellRenderer,
            columns: columns,
            rows: rows,
          ),
        ),
      ));
      expect(find.text('تقرير مالي'), findsOneWidget);
    });

    testWidgets('renders grid footer when provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingScaffold(
          headerTitle: 'Test',
          onRefresh: () {},
          onFullscreen: () {},
          cellRenderer: defaultCellRenderer,
          columns: columns,
          rows: rows,
          gridFooter: const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Total: 100,000'),
          ),
        ),
      ));
      expect(find.text('Total: 100,000'), findsOneWidget);
    });
  });
}
