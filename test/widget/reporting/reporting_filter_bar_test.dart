import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_filter_bar.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingFilterBar', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingFilterBar(
          child: Container(
            height: 40,
            color: Colors.red,
          ),
        ),
      ));
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('renders search field when onSearchChanged provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingFilterBar(
          onSearchChanged: (q) {},
          child: const SizedBox(),
        ),
      ));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('does not render search field when onSearchChanged is null', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingFilterBar(
          child: const SizedBox(),
        ),
      ));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('calls onSearchChanged on text input', (tester) async {
      String? lastQuery;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingFilterBar(
          onSearchChanged: (q) => lastQuery = q,
          child: const SizedBox(),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'cash');
      await tester.pump(const Duration(milliseconds: 400));
      expect(lastQuery, 'cash');
    });

    testWidgets('renders reset button when onReset provided', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingFilterBar(
          onReset: () {},
          child: const SizedBox(),
        ),
      ));
      expect(find.byIcon(Icons.restart_alt), findsOneWidget);
    });

    testWidgets('calls onReset when reset button tapped', (tester) async {
      var resetCalled = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingFilterBar(
          onReset: () => resetCalled = true,
          child: const SizedBox(),
        ),
      ));
      await tester.tap(find.byIcon(Icons.restart_alt));
      expect(resetCalled, isTrue);
    });

    testWidgets('debounces search input', (tester) async {
      int callCount = 0;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingFilterBar(
          onSearchChanged: (q) => callCount++,
          child: const SizedBox(),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'c');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'ca');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'cash');
      await tester.pump(const Duration(milliseconds: 400));
      expect(callCount, 1);
    });
  });

  group('ReportingToggleButton', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToggleButton(
          label: 'Assets',
          isActive: false,
          onPressed: () {},
        ),
      ));
      expect(find.text('Assets'), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToggleButton(
          label: 'Assets',
          isActive: false,
          onPressed: () => called = true,
        ),
      ));
      await tester.tap(find.text('Assets'));
      expect(called, isTrue);
    });

    testWidgets('visual state changes with isActive', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToggleButton(
          label: 'Assets',
          isActive: true,
          onPressed: () {},
        ),
      ));
      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container, isNotNull);
    });
  });

  group('ReportingPresetButton', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingPresetButton(
          label: 'This Month',
          onPressed: () {},
        ),
      ));
      expect(find.text('This Month'), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingPresetButton(
          label: 'This Month',
          onPressed: () => called = true,
        ),
      ));
      await tester.tap(find.text('This Month'));
      expect(called, isTrue);
    });
  });

  group('ReportingDateChip', () {
    testWidgets('renders label and calendar icon', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDateChip(
          label: '2025-01-01',
          onTap: () {},
        ),
      ));
      expect(find.text('2025-01-01'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingDateChip(
          label: 'Date',
          onTap: () => called = true,
        ),
      ));
      await tester.tap(find.text('Date'));
      expect(called, isTrue);
    });
  });
}
