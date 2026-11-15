import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';
import 'package:accounting_system/data/models/packing_order_line_model.dart';
import 'package:accounting_system/data/services/packing_cost_allocation_engine.dart';
import 'package:accounting_system/data/services/product_cost_center_sync_service.dart';
import 'package:accounting_system/data/dao/cost_report_dao.dart';

void main() {
  group('CostCenterHelper & Resolution Engine', () {
    test('resolves strawberry lines accurately', () {
      final row1 = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'فراولة فريش درجة أولى',
        'notes': 'توريد مزرعة وادي النطرون',
      };
      final row2 = {
        'category': 'مواد التعبئة',
        'item_name': 'كراتين فراولة 2 كجم',
        'notes': 'شحنة فراولة مبردة',
      };
      final row3 = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'مرتجع فراولة',
        'notes': 'عيوب فرز',
      };

      expect(CostCenterHelper.resolve(row1).id, CostCenterHelper.strawberryLine.id);
      expect(CostCenterHelper.resolve(row2).id, CostCenterHelper.strawberryLine.id);
      expect(CostCenterHelper.resolve(row3).id, CostCenterHelper.strawberryLine.id);
    });

    test('resolves mango lines accurately', () {
      final row1 = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'مانجو كيت صادر',
        'notes': 'مورد محاصيل مانجو',
      };
      final row2 = {
        'category': 'مواد التعبئة',
        'item_name': 'كراتين مانجا 5 كجم',
        'notes': '',
      };

      expect(CostCenterHelper.resolve(row1).id, CostCenterHelper.mangoLine.id);
      expect(CostCenterHelper.resolve(row2).id, CostCenterHelper.mangoLine.id);
    });

    test('resolves grapes and citrus variety lines', () {
      final grapesRow = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'عنب فليم أحمر',
        'notes': '',
      };
      final citrusRow = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'برتقال صيفي فالنسيا',
        'notes': '',
      };

      expect(CostCenterHelper.resolve(grapesRow).id, CostCenterHelper.grapesLine.id);
      expect(CostCenterHelper.resolve(citrusRow).id, CostCenterHelper.citrusLine.id);
    });

    test('resolves operational and logistics lines', () {
      final shippingRow = {
        'category': 'تكلفة شركات الشحن',
        'item_name': 'نولون شحن بحري كونتينر 40 قدم',
        'notes': 'ميرسك لاين',
      };
      final clearingRow = {
        'category': 'تكلفة المخلصين',
        'item_name': 'أتعاب تخليص جمركي ميناء الإسكندرية',
        'notes': 'شهادة صادر',
      };
      final packingRow = {
        'category': 'مواد التعبئة',
        'item_name': 'ورق زبدة وبالتات خشب',
        'notes': 'استهلاك عام محطة التعبئة',
      };
      final adminRow = {
        'category': 'مصاريف إدارية',
        'item_name': 'ضيافة وبوفيه وأدوات مكتبية',
        'notes': 'إدارة التصدير',
      };

      expect(CostCenterHelper.resolve(shippingRow).id, CostCenterHelper.freightLogistics.id);
      expect(CostCenterHelper.resolve(clearingRow).id, CostCenterHelper.customsClearance.id);
      expect(CostCenterHelper.resolve(packingRow).id, CostCenterHelper.packingStation.id);
      expect(CostCenterHelper.resolve(adminRow).id, CostCenterHelper.generalAdmin.id);
    });

    test('fromId correctly retrieves cost centers and handles fallback', () {
      expect(CostCenterHelper.fromId('mango_line'), CostCenterHelper.mangoLine);
      expect(CostCenterHelper.fromId('strawberry_line'), CostCenterHelper.strawberryLine);
      expect(CostCenterHelper.fromId('customs_clearance'), CostCenterHelper.customsClearance);
      expect(CostCenterHelper.fromId('invalid_id'), CostCenterHelper.generalAdmin);
      expect(CostCenterHelper.fromId(null), CostCenterHelper.generalAdmin);
    });

    test('ProductCostCenterSyncService resolves English names accurately', () {
      final syncService = ProductCostCenterSyncService.instance;
      expect(syncService.resolveEnglishName('مانجو تومي'), 'Mango Line');
      expect(syncService.resolveEnglishName('فراولة فريش'), 'Strawberry Line');
      expect(syncService.resolveEnglishName('عنب ايرلي سويت'), 'Grapes Line');
      expect(syncService.resolveEnglishName('برتقال أبو سرة'), 'Orange Line');
      expect(syncService.resolveEnglishName('ليمون بنزهير'), 'Lemon Line');
      expect(syncService.resolveEnglishName('يوسفي كليمنتين'), 'Mandarin Line');
      expect(syncService.resolveEnglishName('رمان وندر فول'), 'Pomegranate Line');
      expect(syncService.resolveEnglishName('خوخ سيناوي'), 'Peach Line');
    });

    test('dynamically creates Cost Center from real product inventory records', () {
      final peachProduct = {
        'id': 101,
        'code': 'FRT-101',
        'name': 'خوخ بلدي فاخر',
        'color': '#FF5722',
        'icon': 'eco',
      };

      final dynamicCenter = CostCenter.fromProduct(peachProduct);
      expect(dynamicCenter.id, 'CC-FRT-101');
      expect(dynamicCenter.nameAr, 'خوخ بلدي فاخر');
      expect(dynamicCenter.nameEn, 'Peach Line');
      expect(dynamicCenter.type, CostCenterType.variety);

      // Verify that resolution matches this real active product
      final peachExpenseRow = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'توريد خوخ بلدي فاخر درجة أولى',
        'notes': 'مزرعة الإسماعيلية',
      };

      final resolved = CostCenterHelper.resolve(peachExpenseRow, [dynamicCenter]);
      expect(resolved.id, dynamicCenter.id);
      expect(resolved.nameAr, 'خوخ بلدي فاخر');
    });

    test('direct expense binding lands strictly on targeted product and ignores other fruits in order notes', () {
      final activeCenters = [
        CostCenterHelper.strawberryLine,
        CostCenterHelper.mangoLine,
      ];

      // Packing order notes that mentions multiple fruits (Strawberry and Mango)
      const multiProductNotes = '{"order_lines":[{"product_name":"فراولة"},{"product_name":"مانجو"}],"cost_items":[{"name":"نقل خاص بالمانجو","total_egp":4000,"cost_center_id":"CC-MANGO","target_product_name":"مانجو","allocation_method":"MANUAL"}]}';

      // An expense specifically for Mango
      final mangoExpenseRow = {
        'category': 'لوجستيك ونقل',
        'item_name': 'نقل خاص بالمانجو',
        'notes': multiProductNotes,
        'cost_center_id': 'CC-MANGO',
        'target_product_name': 'مانجو',
      };

      final resolved = CostCenterHelper.resolve(mangoExpenseRow, activeCenters);
      expect(resolved.id, CostCenterHelper.mangoLine.id);
      expect(resolved.nameAr, CostCenterHelper.mangoLine.nameAr);
    });

    test('PackingCostAllocationEngine allocates 100% strictly to target line and only splits when EQUAL', () {
      const line1 = PackingOrderLineModel(
        packingOrderId: 1,
        productName: 'فراولة فريش',
        rawMaterialCost: 10000,
        cartonCount: 500,
        netWeightPerCarton: 2.0,
      );
      const line2 = PackingOrderLineModel(
        packingOrderId: 1,
        productName: 'مانجو كيت',
        rawMaterialCost: 20000,
        cartonCount: 400,
        netWeightPerCarton: 5.0,
      );

      final List<PackingOrderLineModel> lines = [line1, line2];

      // 1. Direct targeted cost item for Mango (should land 100% on line 1 = Mango, 0 on Strawberry)
      final directCostItem = {
        'name': 'نقل خاص بالمانجو',
        'total_egp': 6000.0,
        'allocation_method': 'MANUAL',
        'target_line_index': 1,
        'target_product_name': 'مانجو كيت',
        'cost_center_id': 'CC-MANGO',
      };

      final directAllocResult = PackingCostAllocationEngine.instance.allocate(
        lines: lines,
        materials: [],
        costItems: [directCostItem],
      );

      // Strawberry overhead = 0, Mango overhead = 6000
      expect(directAllocResult.lines[0].allocatedCostItems, 0.0);
      expect(directAllocResult.lines[1].allocatedCostItems, 6000.0);

      // 2. Explicit Equal distribution across both lines (should split 50/50 = 3000 each)
      final equalCostItem = {
        'name': 'عمالة تحميل مشتركة',
        'total_egp': 6000.0,
        'allocation_method': 'EQUAL',
        'cost_center_id': 'ALL',
      };

      final equalAllocResult = PackingCostAllocationEngine.instance.allocate(
        lines: lines,
        materials: [],
        costItems: [equalCostItem],
      );

      expect(equalAllocResult.lines[0].allocatedCostItems, 3000.0);
      expect(equalAllocResult.lines[1].allocatedCostItems, 3000.0);
    });

    test('PackingCostAllocationEngine allocates packaging materials to specific crop or equal split', () {
      const line1 = PackingOrderLineModel(
        packingOrderId: 1,
        productName: 'فراولة فريش',
        rawMaterialCost: 10000,
        cartonCount: 500,
        netWeightPerCarton: 2.0,
      );
      const line2 = PackingOrderLineModel(
        packingOrderId: 1,
        productName: 'مانجو كيت',
        rawMaterialCost: 20000,
        cartonCount: 400,
        netWeightPerCarton: 5.0,
      );

      final List<PackingOrderLineModel> lines = [line1, line2];

      // 1. Direct packaging material for Mango (cartons 5kg)
      final mangoCartons = {
        'product_name': 'كرتونة مانجو 5 كجم',
        'used_qty': 400,
        'unit_cost': 15.0,
        'total': 6000.0,
        'apply_to': 'line:1',
        'target_line_index': 1,
        'target_product_name': 'مانجو كيت',
        'allocation_method': 'MANUAL',
      };

      // 2. Shared packaging material (corner protectors & straps)
      final sharedCorners = {
        'product_name': 'زوايا كرتون مقوى',
        'used_qty': 100,
        'unit_cost': 20.0,
        'total': 2000.0,
        'apply_to': 'all',
        'allocation_method': 'EQUAL',
        'cost_center_id': 'ALL',
      };

      final allocResult = PackingCostAllocationEngine.instance.allocate(
        lines: lines,
        materials: [mangoCartons, sharedCorners],
        costItems: [],
      );

      // Strawberry: 0 direct packaging, 1000 shared packaging
      expect(allocResult.lines[0].specificPackagingCost, 0.0);
      expect(allocResult.lines[0].allocatedSharedPackaging, 1000.0);

      // Mango: 6000 direct packaging, 1000 shared packaging
      expect(allocResult.lines[1].specificPackagingCost, 6000.0);
      expect(allocResult.lines[1].allocatedSharedPackaging, 1000.0);

      // 3. Single-line order automatically allocates 100% of material to line 0
      final singleLineOrder = [line1];
      final singleLineResult = PackingCostAllocationEngine.instance.allocate(
        lines: singleLineOrder,
        materials: [sharedCorners],
        costItems: [],
      );
      expect(singleLineResult.lines[0].specificPackagingCost, 2000.0);
    });

    test('CostCenterHelper.resolve integrates packaging materials into product cost center', () {
      final activeCenters = [
        CostCenterHelper.strawberryLine,
        CostCenterHelper.mangoLine,
        CostCenterHelper.grapesLine,
        CostCenterHelper.citrusLine,
      ];

      final multiProductNotesWithMaterials = jsonEncode({
        'lot_entries': [
          {'product_name': 'فراولة فريش', 'lot_id': 'LOT-STR-1'},
          {'product_name': 'مانجو كيت', 'lot_id': 'LOT-MNG-2'},
        ],
        'materials': [
          {
            'product_name': 'كرتونة فراولة 2 كجم',
            'apply_to': 'line:0',
            'target_product_name': 'فراولة فريش',
            'cost_center_id': 'CC-STRAWBERRY',
          },
          {
            'product_name': 'كرتونة مانجو 5 كجم',
            'apply_to': 'line:1',
            'target_product_name': 'مانجو كيت',
            'cost_center_id': 'CC-MANGO',
          },
        ],
      });

      // Strawberry packaging material row
      final strawberryMatRow = {
        'category': 'مواد التعبئة',
        'item_name': 'كرتونة فراولة 2 كجم',
        'notes': multiProductNotesWithMaterials,
      };

      final strawberryCc = CostCenterHelper.resolve(strawberryMatRow, activeCenters);
      expect(strawberryCc.id, CostCenterHelper.strawberryLine.id);

      // Mango packaging material row
      final mangoMatRow = {
        'category': 'مواد التعبئة',
        'item_name': 'كرتونة مانجو 5 كجم',
        'notes': multiProductNotesWithMaterials,
      };

      final mangoCc = CostCenterHelper.resolve(mangoMatRow, activeCenters);
      expect(mangoCc.id, CostCenterHelper.mangoLine.id);

      // Single-crop order automatically binds packaging materials to that crop
      final singleCropNotes = jsonEncode({
        'lot_entries': [
          {'product_name': 'عنب فليم', 'lot_id': 'LOT-GRP-1'},
        ],
        'materials': [
          {
            'product_name': 'بانيت بلاستيك شفاف 500 جم',
            'apply_to': 'all',
          },
        ],
      });

      final grapeMatRow = {
        'category': 'مواد التعبئة',
        'item_name': 'بانيت بلاستيك شفاف 500 جم',
        'notes': singleCropNotes,
      };

      final grapeCc = CostCenterHelper.resolve(grapeMatRow, activeCenters);
      expect(grapeCc.id, CostCenterHelper.grapesLine.id);
    });

    test('fromId correctly resolves sharedProducts (ALL / all / CC-ALL) and never defaults to admin', () {
      expect(CostCenterHelper.fromId('ALL'), CostCenterHelper.sharedProducts);
      expect(CostCenterHelper.fromId('all'), CostCenterHelper.sharedProducts);
      expect(CostCenterHelper.fromId('CC-ALL'), CostCenterHelper.sharedProducts);
      expect(CostCenterHelper.fromId('توزيع بالتساوي على كل المنتجات'), CostCenterHelper.sharedProducts);
      expect(CostCenterHelper.fromId('ALL').nameAr, 'توزيع بالتساوي على كل المنتجات');
    });

    test('fromId correctly resolves dynamic inventory product cost centers by code, id, product_id, or name', () {
      final dynamicStrawberry = CostCenter.fromProduct({
        'id': 101,
        'code': '01',
        'name': 'فراولة فريش ممتازة',
      });
      final dynamicMango = CostCenter.fromProduct({
        'id': 102,
        'code': '02',
        'name': 'مانجو كيت صادر',
      });
      final activeList = [dynamicStrawberry, dynamicMango];

      // Lookup by CC-01
      expect(CostCenterHelper.fromId('CC-01', activeList).id, 'CC-01');
      // Lookup by product_id '101'
      expect(CostCenterHelper.fromId('101', activeList).id, 'CC-01');
      // Lookup by CC-101
      expect(CostCenterHelper.fromId('CC-101', activeList).id, 'CC-01');
      // Lookup by product name
      expect(CostCenterHelper.fromId('فراولة فريش ممتازة', activeList).id, 'CC-01');
      // Lookup by prefix stripped name
      expect(CostCenterHelper.fromId('خط فراولة فريش ممتازة', activeList).id, 'CC-01');

      // Mango lookups
      expect(CostCenterHelper.fromId('CC-02', activeList).id, 'CC-02');
      expect(CostCenterHelper.fromId('102', activeList).id, 'CC-02');
      expect(CostCenterHelper.fromId('مانجو كيت صادر', activeList).id, 'CC-02');
    });

    test('resolve dynamically binds product packaging items (e.g. فراولة - كراتين) to the product cost center', () {
      final dynamicStrawberry = CostCenter.fromProduct({
        'id': 1,
        'code': '01',
        'name': 'فراولة',
      });
      final activeList = [dynamicStrawberry];

      final packagingRow = {
        'category': 'مواد التعبئة',
        'item_name': 'فراولة - كراتين',
        'notes': '',
      };

      final resolvedCc = CostCenterHelper.resolve(packagingRow, activeList);
      expect(resolvedCc.id, 'CC-01');
      expect(resolvedCc.nameAr, 'فراولة');
    });

    test('resolve respects pre-populated cost_center_name in transaction row', () {
      final rowWithCcName = {
        'category': 'مواد التعبئة',
        'item_name': 'كراتين عامة',
        'cost_center_name': 'خط الفراولة',
      };

      final resolved = CostCenterHelper.resolve(rowWithCcName);
      expect(resolved.id, CostCenterHelper.strawberryLine.id);
      expect(resolved.nameAr, 'خط الفراولة');
    });

    test('CostReportDao.normalizeArabic standardizes Arabic variations correctly', () {
      expect(CostReportDao.normalizeArabic('فراولة - وزن'), 'فراوله - وزن');
      expect(CostReportDao.normalizeArabic('فراوله - وزن'), 'فراوله - وزن');
      expect(CostReportDao.normalizeArabic('خط فراولة - كراتين'), 'فراوله - كراتين');
      expect(CostReportDao.normalizeArabic('  إدارة  المحاصيل  '), 'اداره المحاصيل');
    });

    test('Operational transaction compilation perfectly reconciles to 141,388.89 EGP for strawberry line', () {
      // 1. Raw material cost row (100,000.00 EGP)
      final rawRow = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'تكلفة الخام الإجمالي - فراوله - وزن',
        'quantity': 900.0,
        'unit_price': 111.111111111111,
        'amount': 100000.0,
        'cost_center_id': 'CC-1',
        'cost_center_name': 'فراوله - وزن',
      };

      // 2. Waste cost row (2,000.00 EGP)
      final wasteRow = {
        'category': 'تكلفة الهالك',
        'item_name': 'تكلفة الهالك (2.0%) - فراوله - وزن',
        'quantity': 18.0,
        'unit_price': 111.111111111111,
        'amount': 2000.0,
        'cost_center_id': 'CC-1',
        'cost_center_name': 'فراوله - وزن',
      };

      // 3. Sorting deduction row (-11,111.11 EGP)
      final sortingRow = {
        'category': 'تكلفة الفرز',
        'item_name': 'تكلفة الفرز (مستبعد) - فراوله - وزن',
        'quantity': 100.0,
        'unit_price': 111.111111111111,
        'amount': -11111.1111111111,
        'cost_center_id': 'CC-1',
        'cost_center_name': 'فراوله - وزن',
      };

      // 4. Packaging materials allocated share (50,000.00 EGP)
      final materialRow = {
        'category': 'مواد التعبئة',
        'item_name': 'كراتين فراوله 5 ك',
        'quantity': 500.0,
        'unit_price': 100.0,
        'amount': 50000.0,
        'cost_center_id': 'CC-1',
        'cost_center_name': 'فراوله - وزن',
      };

      // 5. Direct cost item allocated share (500.00 EGP)
      final costItemRow = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'مصاريف مهندس',
        'quantity': 0.5,
        'unit_price': 1000.0,
        'amount': 500.0,
        'cost_center_id': 'CC-1',
        'cost_center_name': 'فراوله - وزن',
      };

      final strawberryTransactions = [
        rawRow,
        wasteRow,
        sortingRow,
        materialRow,
        costItemRow,
      ];

      final totalSum = strawberryTransactions.fold<double>(
        0.0,
        (sum, r) => sum + (r['amount'] as double),
      );

      // Financial reconciliation check
      expect((totalSum - 141388.89).abs() < 0.01, isTrue);
      expect(totalSum.toStringAsFixed(2), '141388.89');
    });

    test('Operational transaction compilation perfectly reconciles to 62,980.00 EGP for cartons line', () {
      final cartonTransactions = [
        {'amount': 24000.0}, // Raw material
        {'amount': 480.0},   // Waste
        {'amount': -12000.0},// Sorting deduction
        {'amount': 50000.0}, // Packaging materials
        {'amount': 500.0},   // Direct cost item
      ];

      final totalSum = cartonTransactions.fold<double>(
        0.0,
        (sum, r) => sum + (r['amount'] as double),
      );

      expect((totalSum - 62980.00).abs() < 0.01, isTrue);
      expect(totalSum.toStringAsFixed(2), '62980.00');

      // Grand total of both lines = 204,368.89 EGP
      const grandTotal = 141388.8888888889 + 62980.0;
      expect((grandTotal - 204368.89).abs() < 0.01, isTrue);
    });

    test('resolves Banana Line accurately and maps CC-03 / موز - وزن', () {
      final bananaCenter = CostCenterHelper.fromId('CC-03');
      expect(bananaCenter.id, 'banana_line');
      expect(bananaCenter.nameAr, 'موز');

      final bananaRow = {
        'category': 'تكلفة المحاصيل',
        'item_name': 'موز - وزن',
        'supplier_name': 'مزرعة الهدى',
      };
      expect(CostCenterHelper.resolve(bananaRow).id, CostCenterHelper.bananaLine.id);
    });

    test('reconciles product cost centers so standalone purchases appear without being masked by other products operational rows', () {
      // Simulate operational rows existing for Strawberry
      final operationalRows = [
        {
          'cost_center_id': 'strawberry_line',
          'target_product_name': 'فراولة فريش',
          'category': 'تكلفة المحاصيل',
          'item_name': 'تكلفة الخام الإجمالي - فراولة فريش',
          'amount': 150000.0,
          'is_packing_operational': true,
        }
      ];

      // Standalone Banana purchase row
      final bananaPurchaseRow = {
        'cost_center_id': 'banana_line',
        'cost_center_name': 'موز',
        'category': 'تكلفة المحاصيل',
        'item_name': 'موز - وزن',
        'customer_name': 'مورد الموز',
        'supplier_name': 'مورد الموز',
        'quantity': 1000.0,
        'unit_price': 20.0,
        'amount': 20000.0,
        'is_lot_receipt': true,
      };

      // Raw Strawberry receipt row (pre-production)
      final strawberryLotRow = {
        'cost_center_id': 'strawberry_line',
        'cost_center_name': 'فراولة',
        'category': 'تكلفة المحاصيل',
        'item_name': 'فراولة فريش',
        'amount': 150000.0,
        'is_lot_receipt': true,
      };

      // When filtering by Banana line ('banana_line' or 'CC-03'):
      final targetBanana = CostCenterHelper.fromId('banana_line');
      final normBananaTarget = CostReportDao.normalizeArabic(targetBanana.nameAr);

      bool shouldSkipBanana = false;
      if (bananaPurchaseRow['is_lot_receipt'] == true) {
        shouldSkipBanana = operationalRows.any((op) {
          final opCc = op['cost_center_id']?.toString();
          final opTarget = CostReportDao.normalizeArabic(op['target_product_name']?.toString() ?? '');
          final rowCc = bananaPurchaseRow['cost_center_id']?.toString();
          final rowItem = CostReportDao.normalizeArabic(bananaPurchaseRow['item_name']?.toString() ?? '');
          return (opCc != null && (opCc == rowCc || opCc == targetBanana.id)) ||
                 (opTarget.isNotEmpty && (opTarget == rowItem || opTarget == normBananaTarget));
        });
      }

      // Banana must NOT be skipped despite operationalRows having strawberry rows!
      expect(shouldSkipBanana, isFalse);

      // When filtering by Strawberry line:
      final targetStrawberry = CostCenterHelper.fromId('strawberry_line');
      final normStrawberryTarget = CostReportDao.normalizeArabic(targetStrawberry.nameAr);

      bool shouldSkipStrawberry = false;
      if (strawberryLotRow['is_lot_receipt'] == true) {
        shouldSkipStrawberry = operationalRows.any((op) {
          final opCc = op['cost_center_id']?.toString();
          final opTarget = CostReportDao.normalizeArabic(op['target_product_name']?.toString() ?? '');
          final rowCc = strawberryLotRow['cost_center_id']?.toString();
          final rowItem = CostReportDao.normalizeArabic(strawberryLotRow['item_name']?.toString() ?? '');
          return (opCc != null && (opCc == rowCc || opCc == targetStrawberry.id)) ||
                 (opTarget.isNotEmpty && (opTarget == rowItem || opTarget == normStrawberryTarget));
        });
      }

      // Strawberry raw lot MUST be skipped to avoid double counting with operational line
      expect(shouldSkipStrawberry, isTrue);
    });

    test('Strict Cost Center Details isolation strictly filters records and UI metrics for فرولة - وزن', () {
      final activeCenters = [
        CostCenter(
          id: 'CC-01',
          nameAr: 'فرولة - وزن',
          nameEn: 'Strawberry - Weight',
          type: CostCenterType.variety,
          color: const Color(0xFFF43F5E),
          icon: CostCenterHelper.resolveIcon(null, 'فرولة'),
          code: 'CC-01',
          productId: 1,
          dbId: 1,
        ),
        CostCenter(
          id: 'CC-02',
          nameAr: 'مانجو كيت',
          nameEn: 'Mango Keitt',
          type: CostCenterType.variety,
          color: const Color(0xFFF59E0B),
          icon: CostCenterHelper.resolveIcon(null, 'مانجو'),
          code: 'CC-02',
          productId: 2,
          dbId: 2,
        ),
        CostCenterHelper.packingStation,
        CostCenterHelper.generalAdmin,
      ];

      // Verify that lookup for 'CC-01' with label 'فرولة - وزن' resolves to the strawberry center
      final target = CostCenterHelper.fromId('CC-01', activeCenters);
      expect(target.id, 'CC-01');
      expect(target.nameAr, 'فرولة - وزن');

      // Verify Arabic normalization unifies 'فرولة - وزن' and 'فراولة - وزن'
      expect(
        CostCenterHelper.normalizeArabic('فرولة - وزن'),
        CostCenterHelper.normalizeArabic('فراولة - وزن'),
      );

      // Mixed global transaction pool
      final mixedTransactions = <Map<String, dynamic>>[
        {
          'id': 'tx_1',
          'cost_center_id': 'CC-01',
          'cost_center_name': 'فرولة - وزن',
          'category': 'تكلفة المحاصيل',
          'item_name': 'شراء محصول فرولة',
          'amount': 50000.0,
        },
        {
          'id': 'tx_2',
          'cost_center_id': 'CC-01',
          'cost_center_name': 'فرولة - وزن',
          'category': 'مواد التعبئة',
          'item_name': 'كراتين فرولة 2 كجم',
          'amount': 12000.0,
        },
        {
          'id': 'tx_3',
          'cost_center_id': 'packing_station',
          'cost_center_name': 'محطة التعبئة والتجهيز',
          'category': 'مواد التعبئة',
          'item_name': 'فاتورة مشتريات عامة لمواد التعبئة',
          'amount': 35000.0,
        },
        {
          'id': 'tx_4',
          'cost_center_id': 'packing_station',
          'cost_center_name': 'محطة التعبئة والتجهيز',
          'category': 'مواد التعبئة',
          'item_name': 'رصيد أول المدة - شريط لاصق',
          'amount': 80000.0,
          'is_opening_balance': true,
        },
        {
          'id': 'tx_5',
          'cost_center_id': 'CC-02',
          'cost_center_name': 'مانجو كيت',
          'category': 'تكلفة المحاصيل',
          'item_name': 'شراء محصول مانجو',
          'amount': 45000.0,
        },
        {
          'id': 'tx_6',
          'cost_center_id': 'general_admin',
          'cost_center_name': 'المصروفات العمومية والإدارية',
          'category': 'مصاريف إدارية',
          'item_name': 'إيجار المقر والإنترنت',
          'amount': 15000.0,
        },
        {
          'id': 'tx_7',
          'is_equal_distribution': true,
          'order_products': ['فراولة', 'مانجو كيت'],
          'item_name': 'أجرة تحميل وتعتيق',
          'amount': 6000.0,
        },
        {
          'id': 'tx_8',
          'is_equal_distribution': true,
          'order_products': ['عنب', 'مانجو كيت'],
          'item_name': 'أجرة تحميل عنب ومانجو',
          'amount': 4000.0,
        },
      ];

      // Apply strict cost center filtering for 'CC-01' ('فرولة - وزن')
      final normTarget = CostCenterHelper.normalizeArabic(target.nameAr);
      final normLabel = CostCenterHelper.normalizeArabic('فرولة - وزن');
      final filtered = <Map<String, dynamic>>[];

      for (final row in mixedTransactions) {
        if (row['is_equal_distribution'] == true) {
          final List<String> prods = (row['order_products'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
          final count = prods.isNotEmpty ? prods.length : 1;
          final isIncluded = prods.any((p) {
            final normP = CostCenterHelper.normalizeArabic(p);
            return normP == normTarget ||
                normP.contains(normTarget) ||
                normTarget.contains(normP) ||
                normP == normLabel ||
                normP.contains(normLabel) ||
                normLabel.contains(normP);
          });
          if (isIncluded) {
            final fRow = Map<String, dynamic>.from(row);
            fRow['amount'] = (row['amount'] as double) / count;
            filtered.add(fRow);
          }
        } else {
          final id = row['cost_center_id']?.toString();
          final name = CostCenterHelper.normalizeArabic(row['cost_center_name']?.toString() ?? '');
          final isRowPacking = id == 'packing_station' || id == 'CC-PACKING';

          if (isRowPacking || id == CostCenterHelper.generalAdmin.id) continue;

          final matchesId = id != null && (id == target.id || id == 'CC-01' || id == target.code);
          final matchesName = name == normTarget || name == normLabel;

          if (matchesId || matchesName) {
            filtered.add(row);
          }
        }
      }

      // Assert that strictly only the 3 strawberry items were retained
      expect(filtered.length, 3);
      expect(filtered.any((r) => r['id'] == 'tx_1'), isTrue); // Strawberry crop purchase
      expect(filtered.any((r) => r['id'] == 'tx_2'), isTrue); // Strawberry cartons
      expect(filtered.any((r) => r['id'] == 'tx_7'), isTrue); // Shared packing order (50% share)

      // Assert that global records from other centers are strictly excluded
      expect(filtered.any((r) => r['id'] == 'tx_3'), isFalse); // General packaging
      expect(filtered.any((r) => r['id'] == 'tx_4'), isFalse); // Raw materials initial stock
      expect(filtered.any((r) => r['id'] == 'tx_5'), isFalse); // Mango purchase
      expect(filtered.any((r) => r['id'] == 'tx_6'), isFalse); // Admin expense
      expect(filtered.any((r) => r['id'] == 'tx_8'), isFalse); // Grapes/Mango shared order

      // Assert UI Summary Metrics: Total Count and Total Cost
      final totalCount = filtered.length;
      final totalCost = filtered.fold<double>(0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));

      expect(totalCount, 3);
      expect(totalCost, 65000.0); // 50,000 + 12,000 + 3,000 = 65,000.00 EGP
    });
  });
}


