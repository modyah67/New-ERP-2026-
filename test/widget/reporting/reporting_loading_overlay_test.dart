import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_loading_overlay.dart';

import '../../helpers/test_helpers.dart';

void main() {
  Widget wrapWithStack(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [child],
        ),
      ),
    );
  }

  group('ReportingLoadingOverlay', () {
    testWidgets('shows spinner when visible', (tester) async {
      await tester.pumpWidget(wrapWithStack(
        const ReportingLoadingOverlay(isVisible: true),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides when not visible', (tester) async {
      await tester.pumpWidget(wrapWithStack(
        const ReportingLoadingOverlay(isVisible: false),
      ));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when not visible', (tester) async {
      await tester.pumpWidget(wrapWithStack(
        const ReportingLoadingOverlay(isVisible: false),
      ));
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('is positioned at top-left', (tester) async {
      await tester.pumpWidget(wrapWithStack(
        const ReportingLoadingOverlay(isVisible: true),
      ));
      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.top, 8.0);
      expect(positioned.left, 8.0);
    });
  });
}
