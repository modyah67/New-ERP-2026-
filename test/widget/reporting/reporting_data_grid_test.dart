import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_data_grid.dart';
import 'package:accounting_system/reporting/models/reporting_models.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingDataGrid', () {
    final columns = [
      const ReportColumn(key: 'code', label: 'Code', labelAr: 'الكود', fixedWidth: 100, sortable: true),
      const ReportColumn(key: 'name', label: 'Name', labelAr: 'الاسم', flex: 2, sortable: true),
      const ReportColumn(key: 'debit', label: 'Debit', labelAr: 'المدين', flex: 1, alignRight: true, sortable: true),
      const ReportColumn(key: 'credit', label: 'Credit', labelAr: 'الدائن', flex: 1, alignRight: true, sortable: true),
    ];

    final rows = [
      const ReportingRowData(
        id: '1',
        cells: {'code': '1000', 'name': 'Cash', 'debit': '50000', 'credit': '0'},
      ),
      const ReportingRowData(
        id: '2',
        cells: {'code': '2000', 'name': 'AP', 'debit': '0', 'credit': '30000'},
      ),
      const ReportingRowData(
        id: '3',
        cells: {'code': '3000', 'name': 'Equity', 'debit': '0', 'credit': '20000'},
      ),
    ];

    String defaultCellRenderer(ReportingRowData row, ReportColumn column) {
      return row.cells[column.key]?.toString() ?? '';
    }

    testWidgets('renders column headers', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
        ),
      ));
      expect(find.text('الكود'), findsOneWidget);
      expect(find.text('الاسم'), findsOneWidget);
      expect(find.text('المدين'), findsOneWidget);
      expect(find.text('الدائن'), findsOneWidget);
    });

    testWidgets('renders row data', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
        ),
      ));
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('AP'), findsOneWidget);
    });

    testWidgets('renders empty when no rows', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: [],
          cellRenderer: defaultCellRenderer,
        ),
      ));
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('calls onRowTap when row tapped', (tester) async {
      String? tappedId;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
          onRowTap: (id) => tappedId = id,
        ),
      ));
      await tester.tap(find.text('Cash'));
      expect(tappedId, '1');
    });

    testWidgets('calls onSort when header tapped', (tester) async {
      String? sortKey;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
          onSort: (key) => sortKey = key,
        ),
      ));
      await tester.tap(find.text('الكود'));
      expect(sortKey, 'code');
    });

    testWidgets('shows sort indicator for active column', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
          sortColumn: 'code',
          sortAscending: true,
        ),
      ));
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('shows descending sort indicator', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
          sortColumn: 'code',
          sortAscending: false,
        ),
      ));
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('does not show sort indicator for unsorted column', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
        ),
      ));
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });

    testWidgets('renders expand/collapse for parent rows', (tester) async {
      final hierarchyRows = [
        const ReportingRowData(
          id: 'p1',
          cells: {'code': '1', 'name': 'Assets'},
          hasChildren: true,
          isParent: true,
        ),
        const ReportingRowData(
          id: 'c1',
          cells: {'code': '1000', 'name': 'Cash'},
        ),
      ];
      final depthMap = <String, int>{'p1': 0, 'c1': 1};

      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: hierarchyRows,
          cellRenderer: defaultCellRenderer,
          showHierarchy: true,
          depthMap: depthMap,
        ),
      ));
      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
    });

    testWidgets('calls onExpandToggle when expand arrow tapped', (tester) async {
      String? toggledId;
      final hierarchyRows = [
        const ReportingRowData(
          id: 'p1',
          cells: {'code': '1', 'name': 'Assets'},
          hasChildren: true,
          isParent: true,
        ),
      ];

      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: hierarchyRows,
          cellRenderer: defaultCellRenderer,
          showHierarchy: true,
          onExpandToggle: (id) => toggledId = id,
        ),
      ));
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      expect(toggledId, 'p1');
    });

    testWidgets('shows down arrow when expanded', (tester) async {
      final hierarchyRows = [
        const ReportingRowData(
          id: 'p1',
          cells: {'code': '1', 'name': 'Assets'},
          hasChildren: true,
          isParent: true,
        ),
      ];

      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: hierarchyRows,
          cellRenderer: defaultCellRenderer,
          showHierarchy: true,
          expandedIds: {'p1'},
        ),
      ));
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('renders footer when provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: rows,
          cellRenderer: defaultCellRenderer,
          footer: const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Footer Total'),
          ),
        ),
      ));
      expect(find.text('Footer Total'), findsOneWidget);
    });

    testWidgets('renders parent row with bold font', (tester) async {
      final hierarchyRows = [
        const ReportingRowData(
          id: 'p1',
          cells: {'code': '1', 'name': 'Assets'},
          hasChildren: true,
          isParent: true,
        ),
      ];

      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: hierarchyRows,
          cellRenderer: defaultCellRenderer,
        ),
      ));
      final textWidget = tester.widget<Text>(find.text('Assets'));
      expect(textWidget.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('handles many rows efficiently', (tester) async {
      final manyRows = List.generate(
        100,
        (i) => ReportingRowData(
          id: '$i',
          cells: {'code': '${1000 + i}', 'name': 'Account $i', 'debit': '${i * 100}', 'credit': '0'},
        ),
      );

      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDataGrid(
          columns: columns,
          rows: manyRows,
          cellRenderer: defaultCellRenderer,
        ),
      ));
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
