import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/file_helper.dart';
import '../../../core/theme.dart';
import '../../../data/models/packing_order_model.dart';
import '../../../data/services/packing_calculation_service.dart';
import '../../../data/models/packing_order_line_model.dart';

class PackingExcelExporter {
  static String _fmtWeight(double w) => w.toStringAsFixed(1);
  static String _fmtMoney(double m) => m.toStringAsFixed(2);
  static String _fmtPercent(double p) => p.toStringAsFixed(1);

  static Future<PreparedPackingData?> prepareOrderData(
      PackingOrderModel order) async {
    List<Map<String, dynamic>> materials = [];
    List<Map<String, dynamic>> costItems = [];
    double materialWastePercent = 0.0;
    double totalSortingCost = 0.0;
    double? totalRawWeightKg;
    List<Map<String, dynamic>> wasteDataList = [];

    if (order.notes != null && order.notes!.isNotEmpty) {
      try {
        final notes = jsonDecode(order.notes!) as Map<String, dynamic>;
        materials = (notes['materials'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];
        costItems = (notes['cost_items'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];
        materialWastePercent =
            (notes['material_waste_percent'] as num?)?.toDouble() ?? 0.0;
        totalSortingCost = (notes['sorting_cost'] as num?)?.toDouble() ?? 0.0;
        totalRawWeightKg = (notes['total_raw_weight_kg'] as num?)?.toDouble();

        if (notes['waste_data'] is List) {
          wasteDataList = (notes['waste_data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else if (notes['waste_data'] is Map) {
          wasteDataList = [
            Map<String, dynamic>.from(notes['waste_data'] as Map)
          ];
        }
      } catch (_) {}
    }

    final linesInput = <PackingLineInput>[];
    for (int i = 0; i < order.lines.length; i++) {
      final l = order.lines[i];
      final netWeight = l.netWeightPerCarton * l.cartonCount;
      final effectiveWeight = l.quantity > 0 ? l.quantity : netWeight;

      double lineWasteCost = l.wasteCost;
      double lineWastePercent = 0.0;
      if (i < wasteDataList.length) {
        lineWastePercent =
            (wasteDataList[i]['waste_percent'] as num?)?.toDouble() ?? 0.0;
        if (lineWasteCost == 0 && wasteDataList[i]['waste_cost'] != null) {
          lineWasteCost = (wasteDataList[i]['waste_cost'] as num).toDouble();
        }
      }
      if (lineWastePercent == 0 && lineWasteCost > 0 && l.rawMaterialCost > 0) {
        final pct = (lineWasteCost / l.rawMaterialCost) * 100.0;
        if ((pct - 2.0).abs() < 0.6) {
          lineWastePercent = 2.0;
        } else if ((pct - 5.0).abs() < 0.6) {
          lineWastePercent = 5.0;
        } else {
          lineWastePercent = pct;
        }
      }
      if (lineWasteCost == 0 && lineWastePercent > 0 && l.rawMaterialCost > 0) {
        lineWasteCost = l.rawMaterialCost * (lineWastePercent / 100.0);
      }

      linesInput.add(PackingLineInput(
        productName: l.productName ?? order.productName ?? '',
        cartonCount: l.cartonCount,
        netWeightPerCarton: l.netWeightPerCarton,
        effectiveWeight: effectiveWeight,
        grossWeightPerCarton: l.grossWeightPerCarton > 0
            ? l.grossWeightPerCarton
            : l.netWeightPerCarton,
        productCostPerKg: (order.notes != null && order.notes!.isNotEmpty)
            ? (jsonDecode(order.notes!)['product_cost_per_kg'] as num?)
                    ?.toDouble() ??
                0.0
            : 0.0,
        totalPurchaseCost: l.rawMaterialCost,
        wasteWeight: 0.0,
        sortedWeight: l.sortedWeightKg,
        precomputedWasteCost: lineWasteCost > 0 ? lineWasteCost : null,
        precomputedSortingCost: l.sortingCost > 0 ? l.sortingCost : null,
      ));
    }

    final calcResult = PackingCalculationService.calculateAll(
      lines: linesInput,
      materialItems: materials,
      costItems: costItems,
      materialWastePercent: materialWastePercent,
      totalSortingCost: totalSortingCost,
    );

    final productSummaries = <Map<String, dynamic>>[];
    for (int i = 0; i < order.lines.length; i++) {
      final l = order.lines[i];
      double wPercent = 0.0;
      double wCost = l.wasteCost;
      if (i < wasteDataList.length) {
        wPercent =
            (wasteDataList[i]['waste_percent'] as num?)?.toDouble() ?? 0.0;
        if (wCost == 0 && wasteDataList[i]['waste_cost'] != null) {
          wCost = (wasteDataList[i]['waste_cost'] as num).toDouble();
        }
      }
      if (wPercent == 0 && wCost > 0 && l.rawMaterialCost > 0) {
        final pct = (wCost / l.rawMaterialCost) * 100.0;
        if ((pct - 2.0).abs() < 0.6) {
          wPercent = 2.0;
        } else if ((pct - 5.0).abs() < 0.6) {
          wPercent = 5.0;
        } else {
          wPercent = pct;
        }
      }
      if (wCost == 0 && wPercent > 0 && l.rawMaterialCost > 0) {
        wCost = l.rawMaterialCost * (wPercent / 100.0);
      }

      productSummaries.add({
        'productName': l.productName ?? order.productName ?? '',
        'cartonCount': l.cartonCount,
        'totalNetWeight': l.netWeightPerCarton * l.cartonCount,
        'currency': 'EGP',
        'originalCurrencyTotalCost': l.rawMaterialCost,
        'wastePercent': wPercent,
        'wasteCost': wCost,
      });
    }

    return PreparedPackingData(
      materials: materials,
      costItems: costItems,
      calcResult: calcResult,
      productSummaries: productSummaries,
      totalSortingCost: totalSortingCost,
      totalRawWeightKg: totalRawWeightKg,
    );
  }

  static Future<List<int>?> generateExcelBytes({
    required PackingOrderModel order,
    required PreparedPackingData data,
  }) async {
    return _buildExcel(
      order: order,
      productSummaries: data.productSummaries,
      rawCostItems: data.costItems,
      calc: data.calcResult,
      warehouseName: order.stationId?.toString() ?? 'محطة افتراضية',
      totalSortingCost: data.totalSortingCost,
      totalRawWeightKg: data.totalRawWeightKg,
    );
  }

  static Future<List<int>?> _buildExcel({
    required PackingOrderModel order,
    required List<Map<String, dynamic>> productSummaries,
    required List<Map<String, dynamic>> rawCostItems,
    required PackingCalcResult calc,
    required String warehouseName,
    required double totalSortingCost,
    double? totalRawWeightKg,
  }) async {
    final w = calc.weights;
    final m = calc.materials;
    final c = calc.costItems;
    final f = calc.finalCost;

    final excel = Excel.createExcel();
    final sheet = excel['الملخص'];
    excel.setDefaultSheet('الملخص');
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headerStyle = CellStyle(
      fontSize: 12,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1A5276'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final labelStyle = CellStyle(bold: true, fontSize: 10);

    int row = 0;

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('ملخص أمر التعبئة');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = headerStyle;
    row++;

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('المحطة');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = labelStyle;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = TextCellValue(warehouseName);
    row++;

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('التاريخ');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = labelStyle;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = TextCellValue(DateTime.now().toString().substring(0, 10));
    row++;
    row++;

    void addInfo(String label, dynamic value) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(label);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = labelStyle;
      if (value is num) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = DoubleCellValue(value.toDouble());
      } else {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = TextCellValue(value.toString());
      }
      row++;
    }

    addInfo('عدد المحاصيل', w.totalCrops);
    if (w.totalCrops > 1) {
      for (int i = 0; i < productSummaries.length; i++) {
        final ps = productSummaries[i];
        final wPct = (ps['wastePercent'] as num?)?.toDouble() ?? 0.0;
        final wCost = (ps['wasteCost'] as num?)?.toDouble() ?? 0.0;
        final wasteStr = wCost > 0
            ? (wPct > 0
                ? ' — هالك (${wPct.toStringAsFixed(0)}%): ${_fmtMoney(wCost)} ج.م'
                : ' — هالك: ${_fmtMoney(wCost)} ج.م')
            : '';
        addInfo('  المحصول #${i + 1}',
            '${ps['productName'] ?? "—"} — ${ps['cartonCount']} كرتونة — ${_fmtWeight((ps['totalNetWeight'] as num).toDouble())} كجم$wasteStr');
      }
    }
    row++;

    double fallbackTotalRawWeightKg = 0;
    for (final l in order.lines) {
      final effectiveWeight =
          l.quantity > 0 ? l.quantity : l.netWeightPerCarton * l.cartonCount;
          
      bool isLikelyCartonMode = false;
      if (l.quantity > 0 && l.cartonCount > 0) {
        final ratio = l.quantity / l.cartonCount;
        final diffToCartonMode = (ratio - 1.0).abs();
        final diffToWeightMode = (ratio - l.netWeightPerCarton).abs();
        isLikelyCartonMode = diffToCartonMode < diffToWeightMode;
      }

      if (isLikelyCartonMode) {
        fallbackTotalRawWeightKg += effectiveWeight * l.netWeightPerCarton;
      } else {
        fallbackTotalRawWeightKg += effectiveWeight;
      }
    }

    final finalTotalRawWeightKg = totalRawWeightKg ?? fallbackTotalRawWeightKg;

    addInfo('إجمالي الخام', '${_fmtWeight(finalTotalRawWeightKg)} كجم');
    addInfo('إجمالي الصافي', '${_fmtWeight(w.totalNetWeight)} كجم');
    if (w.totalCartons > 0) addInfo('عدد الكراتين', '${w.totalCartons} كرتونة');
    row++;

    final Map<String, double> currencyTotals = {};
    for (final ps in productSummaries) {
      final cur = (ps['currency'] as String?) ?? 'EGP';
      currencyTotals[cur] = (currencyTotals[cur] ?? 0) +
          (ps['originalCurrencyTotalCost'] as double);
    }
    if (currencyTotals.isNotEmpty) {
      for (final entry in currencyTotals.entries) {
        if (entry.key != 'EGP' && entry.value > 0) {
          addInfo('سعر المحصول (${entry.key})', '${_fmtMoney(entry.value)}');
        }
      }
    }

    addInfo('تكلفة الخام (الإجمالي)', '${_fmtMoney(f.totalRawCost)} ج.م');
    if (f.cropWasteCost > 0) {
      double overallWastePercent = 0.0;
      if (productSummaries.isNotEmpty) {
        final firstPct =
            (productSummaries.first['wastePercent'] as num?)?.toDouble() ?? 0.0;
        if (productSummaries.every(
            (p) => (p['wastePercent'] as num?)?.toDouble() == firstPct)) {
          overallWastePercent = firstPct;
        }
      }
      final pctStr = overallWastePercent > 0
          ? ' (${overallWastePercent.toStringAsFixed(0)}%)'
          : '';
      addInfo('(+) تكلفة الهالك$pctStr', '${_fmtMoney(f.cropWasteCost)} ج.م');
    }
    if (w.totalSortedWeight > 0)
      addInfo('(-) تكلفة الفرز', '${_fmtMoney(totalSortingCost)} ج.م');
    if (w.totalSortedWeight > 0)
      addInfo('= تكلفة المنتج بعد الفرز والهالك',
          '${_fmtMoney(f.fruitCost + f.cropWasteCost)} ج.م');
    row++;
    addInfo('تكلفة مواد التعبئة', '${_fmtMoney(m.materialCost)} ج.م');
    if (m.wastePercent > 0)
      addInfo('+ فاقد مواد التعبئة (${_fmtPercent(m.wastePercent)}%)',
          '${_fmtMoney(m.wasteCost)} ج.م');
    addInfo('التكاليف الإضافية', '${_fmtMoney(c.totalCostItems)} ج.م');
    row++;
    addInfo('إجمالي التكلفة', '${_fmtMoney(f.totalCost)} ج.م');
    if (w.totalCartons > 0)
      addInfo('تكلفة الكرتونة', '${_fmtMoney(f.costPerCarton)} ج.م');

    if (productSummaries.length > 1 && calc.productLines.isNotEmpty) {
      row++;
      row++;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue('ملخص تكلفة المنتجات');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = headerStyle;
      row++;

      final headers = [
        'المنتج',
        'الكراتين',
        'الوزن الصافي',
        'تكلفة الخام الإجمالي',
        'نسبة الهالك',
        'تكلفة الهالك',
        'تكلفة الفرز',
        'تكلفة مواد التعبئة',
        'فاقد المواد',
        'بنود التكلفة',
        'إجمالي تكلفة المنتج',
        'تكلفة الكرتونة'
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
            .value = TextCellValue(headers[i]);
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
                .cellStyle =
            CellStyle(
                bold: true,
                backgroundColorHex: ExcelColor.fromHexString('#2E86C1'),
                fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
      }
      row++;

      for (int i = 0; i < calc.productLines.length; i++) {
        final line = calc.productLines[i];
        final wPct = i < productSummaries.length
            ? (productSummaries[i]['wastePercent'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        int col = 0;
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = TextCellValue(line.productName);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = IntCellValue(line.cartonCount);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.totalNetWeight);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.rawCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = TextCellValue(wPct > 0 ? '${wPct.toStringAsFixed(0)}%' : '0%');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.wasteCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.sortingContribution);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.packagingCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.packagingLoss);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.extraCosts);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.finalCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.cartonCount > 0
                ? (line.finalCost / line.cartonCount)
                : 0);
        row++;
      }
    }

    if (calc.packingLines.isNotEmpty && productSummaries.length > 1) {
      row++;
      row++;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue('تفاصيل التوزيع (السورتينج)');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = headerStyle;
      row++;

      final headers = [
        'المنتج',
        'الوزن الفعلي',
        'تكلفة الكيلو',
        'التكلفة الإجمالية',
        'نسبة الهالك',
        'تكلفة الهالك',
        'تكلفة الفرز'
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
            .value = TextCellValue(headers[i]);
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
                .cellStyle =
            CellStyle(
                bold: true,
                backgroundColorHex: ExcelColor.fromHexString('#28B463'),
                fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
      }
      row++;

      for (int i = 0; i < calc.packingLines.length; i++) {
        final line = calc.packingLines[i];
        final wPct = i < productSummaries.length
            ? (productSummaries[i]['wastePercent'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        int col = 0;
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = TextCellValue(line.productName);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.quantity);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.unitCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.rawMaterialCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = TextCellValue(wPct > 0 ? '${wPct.toStringAsFixed(0)}%' : '0%');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.wasteCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(line.sortingCost);
        row++;
      }
    }

    if (calc.allocationTraces.isNotEmpty && productSummaries.length > 1) {
      row++;
      row++;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue('تفاصيل التوزيع');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = headerStyle;
      row++;

      for (final trace in calc.allocationTraces) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = TextCellValue(trace.itemName);
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
                .cellStyle =
            CellStyle(
                bold: true, fontColorHex: ExcelColor.fromHexString('#D4AC0D'));

        final methodLabel =
            CostAllocationMethod.fromCode(trace.allocationMethod).label;
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = TextCellValue('طريقة التوزيع: $methodLabel');
        row++;

        final headers = ['المحصول', 'النسبة', 'القيمة'];
        for (var i = 0; i < headers.length; i++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
              .value = TextCellValue(headers[i]);
          sheet
                  .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
                  .cellStyle =
              CellStyle(
                  bold: true,
                  backgroundColorHex: ExcelColor.fromHexString('#1A5276'),
                  fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
        }
        row++;

        for (final r in trace.rows) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .value = TextCellValue(r.productName);
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
              .value = TextCellValue('${r.basisPercent.toStringAsFixed(1)}%');
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
              .value = DoubleCellValue(r.allocatedAmount);
          row++;
        }
        row++;
      }
    }

    if (rawCostItems.isNotEmpty) {
      row++;
      row++;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue('تفاصيل التكاليف الإضافية');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = headerStyle;
      row++;

      final headers = [
        'البند',
        'المورد',
        'التكلفة',
        'الكمية',
        'التكلفة الإجمالية'
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
            .value = TextCellValue(headers[i]);
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
                .cellStyle =
            CellStyle(
                bold: true,
                backgroundColorHex: ExcelColor.fromHexString('#D68910'),
                fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
      }
      row++;

      for (final item in rawCostItems) {
        int col = 0;
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = TextCellValue(item['name']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = TextCellValue(item['supplier_name']
                ?.toString() ??
            item['supplierName']?.toString() ??
            '');

        final unitCost = double.tryParse(item['unit_price']?.toString() ??
                item['unit_cost']?.toString() ??
                '0') ??
            0;
        final quantity =
            double.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
        final totalCost = double.tryParse(item['total_egp']?.toString() ??
                item['total']?.toString() ??
                item['total_cost']?.toString() ??
                '0') ??
            0;

        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(unitCost);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(quantity);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: row))
            .value = DoubleCellValue(totalCost);
        row++;
      }
    }

    sheet.setColumnWidth(0, 30);
    for (var i = 1; i <= 9; i++) {
      sheet.setColumnWidth(i, 20);
    }

    return excel.save();
  }

  static Future<void> export(
    BuildContext context, {
    required PackingOrderModel order,
    required List<Map<String, dynamic>> productSummaries,
    required List<Map<String, dynamic>> rawCostItems,
    required PackingCalcResult calc,
    required String warehouseName,
    required double totalSortingCost,
    double? totalRawWeightKg,
  }) async {
    final bytes = await _buildExcel(
      order: order,
      productSummaries: productSummaries,
      rawCostItems: rawCostItems,
      calc: calc,
      warehouseName: warehouseName,
      totalSortingCost: totalSortingCost,
      totalRawWeightKg: totalRawWeightKg,
    );
    if (bytes == null) return;
    final dir = await FileHelper.getExportDirectory();
    final timestamp = DateTime.now()
        .toString()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final file = File('${dir.path}/packing_order_summary_$timestamp.xlsx');
    await file.writeAsBytes(bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم حفظ Excel: ${file.path}',
                textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.success),
      );
    }
  }
}

class PreparedPackingData {
  final List<Map<String, dynamic>> materials;
  final List<Map<String, dynamic>> costItems;
  final PackingCalcResult calcResult;
  final List<Map<String, dynamic>> productSummaries;
  final double totalSortingCost;
  final double? totalRawWeightKg;

  const PreparedPackingData({
    required this.materials,
    required this.costItems,
    required this.calcResult,
    required this.productSummaries,
    required this.totalSortingCost,
    this.totalRawWeightKg,
  });
}
