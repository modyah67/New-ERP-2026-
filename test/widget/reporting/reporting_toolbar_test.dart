import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_toolbar.dart';
import 'package:accounting_system/reporting/models/reporting_models.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ReportingToolbar', () {
    testWidgets('renders refresh button', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToolbar(
          onRefresh: () {},
          onFullscreen: () {},
        ),
      ));
      expect(find.text('تحديث'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_outlined), findsOneWidget);
    });

    testWidgets('renders fullscreen button', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToolbar(
          onRefresh: () {},
          onFullscreen: () {},
        ),
      ));
      expect(find.text('شاشة كاملة'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_outlined), findsOneWidget);
    });

    testWidgets('calls onRefresh when refresh tapped', (tester) async {
      var refreshCalled = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToolbar(
          onRefresh: () => refreshCalled = true,
          onFullscreen: () {},
        ),
      ));
      await tester.tap(find.text('تحديث'));
      expect(refreshCalled, isTrue);
    });

    testWidgets('calls onFullscreen when fullscreen tapped', (tester) async {
      var fullscreenCalled = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToolbar(
          onRefresh: () {},
          onFullscreen: () => fullscreenCalled = true,
        ),
      ));
      await tester.tap(find.text('شاشة كاملة'));
      expect(fullscreenCalled, isTrue);
    });

    testWidgets('renders export actions', (tester) async {
      var exportCalled = false;
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToolbar(
          onRefresh: () {},
          onFullscreen: () {},
          exportActions: [
            ExportAction(
              label: 'تصدير PDF',
              icon: Icons.picture_as_pdf,
              onPressed: () => exportCalled = true,
            ),
          ],
        ),
      ));
      expect(find.text('تصدير PDF'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
      await tester.tap(find.text('تصدير PDF'));
      expect(exportCalled, isTrue);
    });

    testWidgets('renders multiple export actions', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        ReportingToolbar(
          onRefresh: () {},
          onFullscreen: () {},
          exportActions: [
            ExportAction(
              label: 'PDF',
              icon: Icons.picture_as_pdf,
              onPressed: () {},
            ),
            ExportAction(
              label: 'Excel',
              icon: Icons.table_chart,
              onPressed: () {},
            ),
          ],
        ),
      ));
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
    });

    testWidgets('renders in RTL layout', (tester) async {
      await tester.pumpWidget(TestHelpers.wrapInApp(
        Directionality(
          textDirection: TextDirection.rtl,
          child: ReportingToolbar(
            onRefresh: () {},
            onFullscreen: () {},
          ),
        ),
      ));
      expect(find.text('تحديث'), findsOneWidget);
    });
  });
}
