import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';
import 'package:accounting_system/features/exports/widgets/season_rollover_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeasonRolloverDialog Dropdown Assertions & Robustness Tests', () {
    setUp(() {
      //
    });

    Future<void> setDesktop(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1024));
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    testWidgets('Builds without assertion when activeCostCenters has duplicate IDs', (tester) async {
      await setDesktop(tester);
      const center1 = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango',
        type: CostCenterType.variety,
        color: Colors.orange,
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
      );
      const center2 = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027) مكرر',
        nameEn: 'Mango Duplicate',
        type: CostCenterType.variety,
        color: Colors.orange,
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
      );
      const center3 = CostCenter(
        id: 'packing_station',
        nameAr: 'محطة التعبئة',
        nameEn: 'Packing',
        type: CostCenterType.operational,
        color: Colors.blue,
        icon: Icons.inventory,
        code: 'CC-PACKING',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SeasonRolloverDialog.show(
                context,
                costCenter: center1,
                activeCostCenters: const [center1, center2, center3],
                currentNetBalance: 83400.0,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final err = tester.takeException();
      if (err != null) {
        debugPrint('FULL_ERROR: ${err.toString()}');
      }
      expect(err, isNull);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('Builds without assertion when initialCostCenter is not in activeCostCenters', (tester) async {
      await setDesktop(tester);
      const externalCenter = CostCenter(
        id: 'CC-ORANGE-2026-2027',
        nameAr: 'برتقال (موسم 2026-2027)',
        nameEn: 'Orange',
        type: CostCenterType.variety,
        color: Colors.deepOrange,
        icon: Icons.eco,
        code: 'CC-ORANGE-2026-2027',
      );
      const packing = CostCenter(
        id: 'packing_station',
        nameAr: 'محطة التعبئة',
        nameEn: 'Packing',
        type: CostCenterType.operational,
        color: Colors.blue,
        icon: Icons.inventory,
        code: 'CC-PACKING',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SeasonRolloverDialog.show(
                context,
                costCenter: externalCenter,
                activeCostCenters: const [packing],
                currentNetBalance: 50000.0,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('Builds without assertion when IDs differ only by casing', (tester) async {
      await setDesktop(tester);
      const lowerCenter = CostCenter(
        id: 'cc-mango-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango',
        type: CostCenterType.variety,
        color: Colors.orange,
        icon: Icons.eco,
        code: 'cc-mango-2026-2027',
      );
      const upperCenter = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango',
        type: CostCenterType.variety,
        color: Colors.orange,
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SeasonRolloverDialog.show(
                context,
                costCenter: lowerCenter,
                activeCostCenters: const [upperCenter],
                currentNetBalance: 83400.0,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('Builds gracefully when activeCostCenters is empty', (tester) async {
      await setDesktop(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SeasonRolloverDialog.show(
                context,
                activeCostCenters: const [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('SeasonRolloverDialog Stage 1 vs Stage 2 Rollover Logic Tests', () {
    Future<void> setDesktop(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1024));
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('Stage 1 closure preserves current season year and generates Period 2 name & code', (tester) async {
      await setDesktop(tester);
      const stage1Center = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango',
        type: CostCenterType.variety,
        color: Colors.orange,
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
        season: '2026-2027',
        seasonNumber: 1,
        closureCount: 0,
        seasonStatus: 'active',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SeasonRolloverDialog.show(
                context,
                costCenter: stage1Center,
                activeCostCenters: const [stage1Center],
                currentNetBalance: 50000.0,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Verify Header and Period indicator
      expect(find.text('إقفال وترحيل الفترة (الموسم الأول ← الثاني)'), findsOneWidget);
      expect(find.text('فترة 1/2'), findsWidgets);

      // Verify Intra-card Rollover Banner (within same card, no new card created)
      expect(find.text('الترحيل داخل نفس كارت مركز التكلفة الحالي:'), findsOneWidget);
      expect(find.textContaining('بدون إنشاء أي كارت جديد'), findsOneWidget);
      expect(find.text('تأكيد ترحيل الفترة الأولى إلى الفترة الثانية'), findsOneWidget);

      // Verify no -P2 target code is generated or displayed
      expect(find.textContaining('-P2'), findsNothing);
    });

    testWidgets('Stage 2 closure increments season year and generates new year name & code', (tester) async {
      await setDesktop(tester);
      const stage2Center = CostCenter(
        id: 'CC-MANGO-2026-2027-P2',
        nameAr: 'مانجو (موسم 2026-2027 - الفترة 2)',
        nameEn: 'Mango Period 2',
        type: CostCenterType.variety,
        color: Colors.orange,
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027-P2',
        season: '2026-2027',
        seasonNumber: 2,
        closureCount: 1,
        seasonStatus: 'active',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SeasonRolloverDialog.show(
                context,
                costCenter: stage2Center,
                activeCostCenters: const [stage2Center],
                currentNetBalance: 35000.0,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Verify Header indicates Final Closure
      expect(find.text('الإقفال النهائي للسنة الزراعية'), findsWidgets);
      expect(find.text('فترة 2/2'), findsWidgets);

      // Verify Input text field has incremented next year: '2027-2028'
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, '2027-2028');

      // Verify Input label
      expect(find.text('السنة الزراعية الجديدة القادمة:'), findsOneWidget);

      // Verify Preview Target Center Name contains 'موسم 2027-2028' without 'الفترة 2'
      expect(find.textContaining('مانجو (موسم 2027-2028)'), findsOneWidget);

      // Verify Preview Target Code has no '-P2' suffix
      expect(find.textContaining('CC-MANGO-2027-2028'), findsOneWidget);
      expect(find.textContaining('CC-MANGO-2027-2028-P2'), findsNothing);

      // Verify Action Button Label
      expect(find.text('تأكيد الإقفال النهائي وإنشاء السنة الجديدة'), findsOneWidget);
    });
  });
}

