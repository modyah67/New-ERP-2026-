import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/reporting/widgets/reporting_page_header.dart';
import 'package:accounting_system/reporting/widgets/reporting_summary_cards.dart';
import 'package:accounting_system/reporting/widgets/reporting_toolbar.dart';
import 'package:accounting_system/reporting/widgets/reporting_empty_state.dart';
import 'package:accounting_system/reporting/widgets/reporting_error_view.dart';
import 'package:accounting_system/reporting/models/reporting_models.dart';

import '../helpers/test_helpers.dart';


void main() {
  group('Golden Tests', () {
    testWidgets('ReportingPageHeader - RTL', (tester) async {
      await tester.pumpWidget(
        TestHelpers.wrapInApp(
          Directionality(
            textDirection: TextDirection.rtl,
            child: const ReportingPageHeader(
              title: 'ميزان المراجعة',
              count: 42,
              countLabel: 'حساب',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReportingPageHeader),
        matchesGoldenFile('golden/reporting_page_header_rtl.png'),
      );
    });

    testWidgets('ReportingPageHeader - Desktop', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TestHelpers.wrapInApp(
          Directionality(
            textDirection: TextDirection.rtl,
            child: const ReportingPageHeader(
              title: 'ميزان المراجعة',
              count: 42,
              countLabel: 'حساب',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReportingPageHeader),
        matchesGoldenFile('golden/reporting_page_header_desktop.png'),
      );
    });

    testWidgets('ReportingSummaryCards - RTL', (tester) async {
      await tester.pumpWidget(
        TestHelpers.wrapInApp(
          Directionality(
            textDirection: TextDirection.rtl,
            child: const ReportingSummaryCards(
              metrics: [
                MetricData(
                  title: 'إجمالي المدين',
                  value: '500,000',
                  icon: Icons.trending_up,
                  color: Colors.green,
                ),
                MetricData(
                  title: 'إجمالي الدائن',
                  value: '480,000',
                  icon: Icons.trending_down,
                  color: Colors.red,
                ),
                MetricData(
                  title: 'الفرق',
                  value: '20,000',
                  icon: Icons.account_balance,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReportingSummaryCards),
        matchesGoldenFile('golden/reporting_summary_cards_rtl.png'),
      );
    });

    testWidgets('ReportingToolbar - RTL', (tester) async {
      await tester.pumpWidget(
        TestHelpers.wrapInApp(
          Directionality(
            textDirection: TextDirection.rtl,
            child: ReportingToolbar(
              onRefresh: () {},
              onFullscreen: () {},
              exportActions: [
                ExportAction(
                  label: 'تصدير PDF',
                  icon: Icons.picture_as_pdf,
                  onPressed: () {},
                ),
                ExportAction(
                  label: 'تصدير Excel',
                  icon: Icons.table_chart,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReportingToolbar),
        matchesGoldenFile('golden/reporting_toolbar_rtl.png'),
      );
    });

    testWidgets('ReportingEmptyState - RTL', (tester) async {
      await tester.pumpWidget(
        TestHelpers.wrapInApp(
          Directionality(
            textDirection: TextDirection.rtl,
            child: const ReportingEmptyState(
              title: 'لا توجد بيانات',
              subtitle: 'أضف المعاملات للبدء',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReportingEmptyState),
        matchesGoldenFile('golden/reporting_empty_state_rtl.png'),
      );
    });

    testWidgets('ReportingErrorView - RTL', (tester) async {
      await tester.pumpWidget(
        TestHelpers.wrapInApp(
          Directionality(
            textDirection: TextDirection.rtl,
            child: ReportingErrorView(
              message: 'حدث خطأ في تحميل البيانات',
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReportingErrorView),
        matchesGoldenFile('golden/reporting_error_view_rtl.png'),
      );
    });

    testWidgets('ReportingSummaryCards - Desktop layout', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TestHelpers.wrapInApp(
          Directionality(
            textDirection: TextDirection.rtl,
            child: const ReportingSummaryCards(
              metrics: [
                MetricData(
                  title: 'إجمالي المدين',
                  value: '500,000',
                  icon: Icons.trending_up,
                  color: Colors.green,
                ),
                MetricData(
                  title: 'إجمالي الدائن',
                  value: '480,000',
                  icon: Icons.trending_down,
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ReportingSummaryCards),
        matchesGoldenFile('golden/reporting_summary_cards_desktop.png'),
      );
    });
  });
}
