import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';
import 'package:accounting_system/data/models/treasury_model.dart';
import 'package:accounting_system/data/services/cost_center_service.dart';

void main() {
  group('Agricultural Crop-Centric Cost Center & Seasonal Lifecycle Tests', () {
    test('canonicalCropName unifies fruit purchasing methods into singular crop line', () {
      // Mango variations
      expect(CostCenter.canonicalCropName('مانجو - وزن'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('مانجو - كرتون'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('مانجو (وزن)'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('مانجو (كرتون)'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('مانجو قطاعي'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('مانجو جملة'), equals('مانجو'));
      expect(CostCenter.canonicalCropName('Mango - Weight'), equals('Mango'));
      expect(CostCenter.canonicalCropName('Mango - Carton'), equals('Mango'));

      // Grapes variations
      expect(CostCenter.canonicalCropName('عنب - وزن'), equals('عنب'));
      expect(CostCenter.canonicalCropName('عنب - كرتون'), equals('عنب'));
      expect(CostCenter.canonicalCropName('عنب فريش'), equals('عنب'));

      // Strawberry variations
      expect(CostCenter.canonicalCropName('فراولة - وزن'), equals('فراولة'));
      expect(CostCenter.canonicalCropName('فراولة خام'), equals('فراولة'));

      // Citrus & Banana
      expect(CostCenter.canonicalCropName('برتقال - كرتون'), equals('برتقال'));
      expect(CostCenter.canonicalCropName('موز - كرتون'), equals('موز'));
    });

    test('resolveCropSlug maps unified canonical crops to consistent slugs', () {
      expect(CostCenter.resolveCropSlug('مانجو - وزن'), equals('MANGO'));
      expect(CostCenter.resolveCropSlug('مانجو - كرتون'), equals('MANGO'));
      expect(CostCenter.resolveCropSlug('عنب (كرتون)'), equals('GRAPES'));
      expect(CostCenter.resolveCropSlug('فراولة - وزن'), equals('STRAWBERRY'));
      expect(CostCenter.resolveCropSlug('برتقال'), equals('ORANGE'));
      expect(CostCenter.resolveCropSlug('ليمون بلدي'), equals('LEMON'));
      expect(CostCenter.resolveCropSlug('موز'), equals('BANANA'));
    });

    test('formatSeasonalName generates standard IAS 41 seasonal naming', () {
      expect(
        CostCenterService.formatSeasonalName(cropName: 'عنب', season: '2026-2027'),
        equals('عنب 2026-2027'),
      );
      expect(
        CostCenterService.formatSeasonalName(cropName: 'مانجو - وزن', season: '2026'),
        equals('مانجو 2026'),
      );
    });

    test('CostCenter model serializes and deserializes seasonal and crop fields', () {
      const model = CostCenter(
        id: 'CC-CROP-MANGO-2026',
        nameAr: 'مانجو 2026',
        nameEn: 'Mango 2026',
        code: 'CC-CROP-MANGO-2026',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        cropName: 'مانجو',
        cropCode: 'MANGO',
        season: '2026',
        seasonStatus: 'active',
        openingBalance: 150000.0,
        currentBalance: 320000.0,
        branchId: 80001,
        rolloverCostCenterId: 'cc_mango_2025',
      );

      final map = model.toMap();
      expect(map['crop_name'], equals('مانجو'));
      expect(map['crop_code'], equals('MANGO'));
      expect(map['season'], equals('2026'));
      expect(map['season_status'], equals('active'));
      expect(map['opening_balance'], equals(150000.0));
      expect(map['current_balance'], equals(320000.0));
      expect(map['branch_id'], equals(80001));
      expect(map['rollover_cost_center_id'], equals('cc_mango_2025'));

      final reconstructed = CostCenter.fromMap(map);
      expect(reconstructed.id, equals('CC-CROP-MANGO-2026'));
      expect(reconstructed.nameAr, equals('مانجو 2026'));
      expect(reconstructed.cropName, equals('مانجو'));
      expect(reconstructed.cropCode, equals('MANGO'));
      expect(reconstructed.season, equals('2026'));
      expect(reconstructed.seasonStatus, equals('active'));
      expect(reconstructed.openingBalance, equals(150000.0));
      expect(reconstructed.currentBalance, equals(320000.0));
      expect(reconstructed.branchId, equals(80001));
      expect(reconstructed.rolloverCostCenterId, equals('cc_mango_2025'));
    });

    test('TreasuryTransactionModel binds branch and cost center for expense & transfer audit', () {
      final txMap = <String, dynamic>{
        'id': 9901,
        'treasury_id': 1,
        'type': 'expense',
        'currency': 'EGP',
        'amount': -45000.0,
        'description': 'صرف مستلزمات حصاد وتعبئة',
        'cost_center_id': 'CC-CROP-GRAPES-2026-2027',
        'branch_id': 80002,
        'to_branch_id': 80005,
        'to_cost_center_id': 'CC-CROP-GRAPES-2026-2027',
        'created_at': '2026-09-11T12:00:00Z',
      };

      final tx = TreasuryTransactionModel.fromMap(txMap);
      expect(tx.id, equals('9901'));
      expect(tx.costCenterId, equals('CC-CROP-GRAPES-2026-2027'));
      expect(tx.branchId, equals('80002'));
      expect(tx.toBranchId, equals('80005'));
      expect(tx.toCostCenterId, equals('CC-CROP-GRAPES-2026-2027'));
    });

    test('CostCenterHelper.fromId resolves static varieties and fallback gracefully', () {
      final mangoCenter = CostCenterHelper.fromId('mango_line');
      expect(mangoCenter.nameAr, contains('مانجو'));
      expect(mangoCenter.type, equals(CostCenterType.variety));

      // Unknown IDs gracefully fallback to General Admin rather than crashing
      final unknownCenter = CostCenterHelper.fromId('unknown_custom_id');
      expect(unknownCenter.id, equals(CostCenterHelper.generalAdmin.id));
      expect(unknownCenter.nameAr, contains('عمومية'));
    });

    test('Strict Two-Stage Seasonal Closure properties and status transitions', () {
      // Stage 1: Initial season (Season 1)
      const season1Active = CostCenter(
        id: 'CC-CROP-MANGO-2026',
        nameAr: 'مانجو 2026',
        nameEn: 'Mango 2026',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        season: '2026',
        seasonStatus: 'active',
        seasonNumber: 1,
        closureCount: 0,
        isActive: true,
      );

      expect(season1Active.closureCount, equals(0));
      expect(season1Active.seasonNumber, equals(1));
      expect(season1Active.isClosed, isFalse);
      expect(season1Active.isPermanentlyClosed, isFalse);
      expect(season1Active.canClose, isTrue);
      expect(season1Active.isFinalSeason, isFalse);
      expect(season1Active.closureStageLabel, equals('الموسم الأول'));

      // Stage 1: After Season 1 closure
      final season1Closed = season1Active.copyWith(
        seasonStatus: 'closed',
        closureCount: 1,
        isActive: false,
      );

      expect(season1Closed.isClosed, isTrue);
      expect(season1Closed.isPermanentlyClosed, isFalse);
      expect(season1Closed.canClose, isFalse);
      expect(season1Closed.closureStageLabel, equals('الموسم مقفل'));

      // Stage 2: Initialized Season 2 (Period 2) center
      const season2Active = CostCenter(
        id: 'CC-CROP-MANGO-2026-S2',
        nameAr: 'مانجو 2026 - موسم 2',
        nameEn: 'Mango 2026 - Season 2',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        season: '2026 - موسم 2',
        seasonStatus: 'active',
        seasonNumber: 2,
        closureCount: 0,
        isActive: true,
      );

      expect(season2Active.closureCount, equals(0));
      expect(season2Active.seasonNumber, equals(2));
      expect(season2Active.isClosed, isFalse);
      expect(season2Active.isPermanentlyClosed, isFalse);
      expect(season2Active.canClose, isTrue);
      expect(season2Active.isFinalSeason, isTrue);
      expect(season2Active.closureStageLabel, equals('الموسم الثاني (الأخير)'));

      // Stage 3: After Season 2 closure (Permanent Closure of the Year)
      final permanentlyClosedByStatus = season2Active.copyWith(
        seasonStatus: 'permanently_closed',
        closureCount: 2,
        isActive: false,
      );

      expect(permanentlyClosedByStatus.isClosed, isTrue);
      expect(permanentlyClosedByStatus.isPermanentlyClosed, isTrue);
      expect(permanentlyClosedByStatus.canClose, isFalse);
      expect(permanentlyClosedByStatus.closureStageLabel, equals('السنة مقفلة نهائياً'));

      // Also permanently closed if closureCount >= 2 regardless of status string
      const permanentlyClosedByCount = CostCenter(
        id: 'CC-EXHAUSTED',
        nameAr: 'مركز مستنفد',
        nameEn: 'Exhausted Center',
        type: CostCenterType.variety,
        color: Color(0xFF9E9E9E),
        icon: Icons.lock,
        closureCount: 2,
        seasonNumber: 2,
        isActive: false,
      );

      expect(permanentlyClosedByCount.isPermanentlyClosed, isTrue);
      expect(permanentlyClosedByCount.canClose, isFalse);
      expect(permanentlyClosedByCount.closureStageLabel, equals('السنة مقفلة نهائياً'));
    });

    test('CostCenter serializes and deserializes closure_count and season_number', () {
      const center = CostCenter(
        id: 'CC-CROP-ORANGE-2026',
        nameAr: 'برتقال 2026',
        nameEn: 'Orange 2026',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        season: '2026',
        seasonStatus: 'active',
        closureCount: 1,
        seasonNumber: 2,
      );

      final map = center.toMap();
      expect(map['closure_count'], equals(1));
      expect(map['season_number'], equals(2));

      final restored = CostCenter.fromMap(map);
      expect(restored.closureCount, equals(1));
      expect(restored.seasonNumber, equals(2));
    });

    test('CostCenter fromMap defaults closure_count to 0 and season_number to 1 when absent', () {
      final legacyMap = <String, dynamic>{
        'id': 1001,
        'code': 'CC-LEGACY',
        'name_ar': 'مركز قديم',
        'cost_center_type': 'variety',
        'status': 'active',
      };

      final legacyCenter = CostCenter.fromMap(legacyMap);
      expect(legacyCenter.closureCount, equals(0));
      expect(legacyCenter.seasonNumber, equals(1));
      expect(legacyCenter.isPermanentlyClosed, isFalse);
      expect(legacyCenter.canClose, isTrue);
    });

    test('CostCenterHelper.fromId prioritizes active seasonal cost center over closed seasons', () {
      const closedSeason1 = CostCenter(
        id: 'CC-MANGO-2025-2026',
        nameAr: 'مانجو (موسم 2025-2026)',
        nameEn: 'Mango Season 1',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        code: 'CC-MANGO-2025-2026',
        cropName: 'مانجو',
        cropCode: 'MANGO',
        season: '2025-2026',
        seasonStatus: 'closed',
        seasonNumber: 1,
        isActive: false,
      );

      const activeSeason2 = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango Season 2',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
        cropName: 'مانجو',
        cropCode: 'MANGO',
        season: '2026-2027',
        seasonStatus: 'active',
        seasonNumber: 2,
        isActive: true,
      );

      final List<CostCenter> activeCenters = [closedSeason1, activeSeason2];

      // 1. Resolve by canonical crop name
      final resolvedFromCrop = CostCenterHelper.fromId('مانجو', activeCenters);
      expect(resolvedFromCrop.id, equals('CC-MANGO-2026-2027'));
      expect(resolvedFromCrop.isActiveSeason, isTrue);

      // 2. Resolve from purchase mode variant (e.g., raw return or packing item "مانجو كرتون")
      final resolvedFromCarton = CostCenterHelper.fromId('مانجو كرتون', activeCenters);
      expect(resolvedFromCarton.id, equals('CC-MANGO-2026-2027'));

      // 3. Resolve from weight variant "مانجو - وزن"
      final resolvedFromWeight = CostCenterHelper.fromId('مانجو - وزن', activeCenters);
      expect(resolvedFromWeight.id, equals('CC-MANGO-2026-2027'));
    });

    test('CostCenter displayTitle outputs canonical seasonal label correctly', () {
      const center = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو',
        nameEn: 'Mango',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        season: '2026-2027',
        seasonStatus: 'active',
      );
      expect(center.displayTitle, equals('مانجو (موسم 2026-2027)'));

      // If already formatted with season, does not double-format
      const formattedCenter = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        season: '2026-2027',
        seasonStatus: 'active',
      );
      expect(formattedCenter.displayTitle, equals('مانجو (موسم 2026-2027)'));
    });

    test('CostCenterHelper.resolve binds returns, sorting sales, and packing materials to active seasonal center', () {
      const activeMangoSeason = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango Season 2026-2027',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
        cropName: 'مانجو',
        cropCode: 'MANGO',
        season: '2026-2027',
        seasonStatus: 'active',
        seasonNumber: 1,
        isActive: true,
      );

      final List<CostCenter> activeCenters = [activeMangoSeason];

      // 1. Crop Return transaction row
      final returnRow = {
        'item_name': 'مرتجع محصول خام مانجو كيت',
        'target_product_name': 'مانجو',
        'source_type': 'lot_return',
        'category': 'تكلفة المحاصيل',
      };
      final resolvedReturnCenter = CostCenterHelper.resolve(returnRow, activeCenters);
      expect(resolvedReturnCenter.id, equals('CC-MANGO-2026-2027'));

      // 2. Sorting Sale transaction row
      final sortingSaleRow = {
        'item_name': 'إيراد بيع فرز - مانجو',
        'target_product_name': 'مانجو كرتون',
        'source_type': 'sorting_sale',
        'category': 'تكلفة الفرز',
      };
      final resolvedSortingCenter = CostCenterHelper.resolve(sortingSaleRow, activeCenters);
      expect(resolvedSortingCenter.id, equals('CC-MANGO-2026-2027'));

      // 3. Packaging Material row assigned to target product
      final packagingRow = {
        'item_name': 'كرتونة مانجو 5 كجم',
        'target_product_name': 'مانجو كرتون',
        'category': 'مواد التعبئة',
      };
      final resolvedPackagingCenter = CostCenterHelper.resolve(packagingRow, activeCenters);
      expect(resolvedPackagingCenter.id, equals('CC-MANGO-2026-2027'));
    });

    test('Net cost calculation accurately offsets gross purchase with returns and sorting sales', () {
      // Raw purchase: +100,000 EGP
      const rawPurchase = 100000.0;
      // Crop return: -15,000 EGP (returned to supplier)
      final cropReturn = -15000.0.abs();
      // Sorting sale: -10,000 EGP (revenue from produce sorting sale offsetting costs)
      final sortingSale = -10000.0.abs();
      // Packaging material: +8,000 EGP
      const packagingCost = 8000.0;

      final netCenterCost = rawPurchase + cropReturn + sortingSale + packagingCost;

      // Net cost should be 100,000 - 15,000 - 10,000 + 8,000 = 83,000 EGP
      expect(netCenterCost, equals(83000.0));
    });

    test('Purchases and returns route to identical unified seasonal cost center ID and displayTitle', () {
      const activeMangoSeason = CostCenter(
        id: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango Season 2026-2027',
        type: CostCenterType.variety,
        color: Color(0xFFFF9800),
        icon: Icons.eco,
        code: 'CC-MANGO-2026-2027',
        cropName: 'مانجو',
        cropCode: 'MANGO',
        season: '2026-2027',
        seasonStatus: 'active',
        seasonNumber: 1,
        isActive: true,
      );

      final List<CostCenter> centers = [activeMangoSeason];

      // 1. Purchase for "مانجو - وزن"
      final purchaseCenter = CostCenterHelper.fromId('مانجو - وزن', centers);
      expect(purchaseCenter.id, equals('CC-MANGO-2026-2027'));
      expect(purchaseCenter.code, equals('CC-MANGO-2026-2027'));
      expect(purchaseCenter.displayTitle, equals('مانجو (موسم 2026-2027)'));

      // 2. Return for the same lot / item "مانجو - وزن"
      final returnCenter = CostCenterHelper.fromId('مانجو - وزن', centers);
      expect(returnCenter.id, equals(purchaseCenter.id));
      expect(returnCenter.code, equals(purchaseCenter.code));
      expect(returnCenter.displayTitle, equals(purchaseCenter.displayTitle));

      // 3. Purchase for "مانجو كرتون"
      final cartonPurchaseCenter = CostCenterHelper.fromId('مانجو كرتون', centers);
      expect(cartonPurchaseCenter.id, equals(purchaseCenter.id));
      expect(cartonPurchaseCenter.displayTitle, equals(purchaseCenter.displayTitle));

      // 4. Verify transaction records reconciliation in cost center ledger
      final purchaseTransaction = {
        'cost_center_id': purchaseCenter.code,
        'cost_center_name': purchaseCenter.displayTitle,
        'source_type': 'lot_receipt',
        'category': 'تكلفة المحاصيل',
        'quantity': 900.0,
        'amount': 45000.0,
      };

      final returnTransaction = {
        'cost_center_id': returnCenter.code,
        'cost_center_name': returnCenter.displayTitle,
        'source_type': 'lot_return',
        'category': 'تكلفة المحاصيل',
        'quantity': -400.0,
        'amount': -20000.0,
      };

      // Ensure identical cost center binding
      expect(returnTransaction['cost_center_id'], equals(purchaseTransaction['cost_center_id']));
      expect(returnTransaction['cost_center_name'], equals(purchaseTransaction['cost_center_name']));
      expect(returnTransaction['category'], equals(purchaseTransaction['category']));

      // Net quantity and cost within that seasonal cost center
      final netQty = (purchaseTransaction['quantity'] as double) + (returnTransaction['quantity'] as double);
      final netAmount = (purchaseTransaction['amount'] as double) + (returnTransaction['amount'] as double);

      expect(netQty, equals(500.0));
      expect(netAmount, equals(25000.0));
    });
  });
}

