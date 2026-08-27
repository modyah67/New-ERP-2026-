import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/supplier_settlement_model.dart';
import '../../data/models/prep_center_cost_item_model.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/shipment_recipe_snapshot_model.dart';
import '../../data/services/prep_center_breakdown_adapter.dart';
import '../../core/services/shipment_profitability_service.dart';

class PrepCenterInvoicePdfService {
  static Future<void> previewPdf({
    required m.BuildContext context,
    required ExportShipmentModel shipment,
    List<Map<String, dynamic>> shipmentItems = const [],
    required List<SupplierSettlementModel> settlements,
    required List<PrepCenterCostItemModel> costItems,
    required List<PackingOrderModel> packingOrders,
    required List<ShipmentRecipeSnapshotModel> recipes,
    PrepCenterBreakdownResult breakdownResult = const PrepCenterBreakdownResult(),
    ShipmentProfitabilityResult? profitabilityResult,
  }) async {
    final doc = await _generate(shipment, shipmentItems, settlements, costItems, packingOrders, recipes, breakdownResult, profitabilityResult);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static Future<pw.Document> _generate(
    ExportShipmentModel s,
    List<Map<String, dynamic>> shipmentItems,
    List<SupplierSettlementModel> settlements,
    List<PrepCenterCostItemModel> costItems,
    List<PackingOrderModel> packingOrders,
    List<ShipmentRecipeSnapshotModel> recipes,
    PrepCenterBreakdownResult breakdown,
    ShipmentProfitabilityResult? profitabilityResult,
  ) async {
    final doc = pw.Document();
    late final pw.Font fontBase;
    late final pw.Font fontBold_;
    try {
      final fr = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fb = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      fontBase = pw.Font.ttf(fr);
      fontBold_ = pw.Font.ttf(fb);
    } catch (_) {
      fontBase = pw.Font.helvetica();
      fontBold_ = pw.Font.helveticaBold();
    }

    final useBreakdown = breakdown.hasData;

    const packingTypes = {'PACKAGING', 'LABELS', 'STICKERS'};
    final totalSupplierAmount = useBreakdown
        ? breakdown.totalSupplierAmount
        : settlements.fold<double>(0.0, (a, r) => a + r.totalAmount);
    final totalPackingCost = useBreakdown
        ? breakdown.totalPackingCost
        : costItems.where((c) => packingTypes.contains(c.costType)).fold<double>(0.0, (a, r) => a + r.totalCost);
    final totalLogisticsCost = useBreakdown
        ? breakdown.totalLogisticsCost
        : costItems.where((c) => c.costType == 'TRANSPORT' || c.costType == 'DIESEL' || c.costType == 'COOLING').fold<double>(0.0, (a, r) => a + r.totalCost);
    final totalAdminCost = useBreakdown
        ? breakdown.totalAdminCost
        : costItems.fold<double>(0.0, (a, r) => a + r.totalCost) - totalPackingCost - totalLogisticsCost;
    final totalCostItemsAmount = totalPackingCost + totalLogisticsCost + totalAdminCost;
    final grandTotal = useBreakdown ? breakdown.grandTotalCost : totalSupplierAmount + totalCostItemsAmount;
    final revenue = profitabilityResult?.revenueEgp ?? s.totalRevenueEgp;
    final netProfit = profitabilityResult?.netProfit ?? (revenue - grandTotal);
    final margin = profitabilityResult?.netMargin ?? (revenue > 0 ? (netProfit / revenue * 100) : 0.0);
    final roi = grandTotal > 0 ? (netProfit / grandTotal * 100) : 0.0;
    final totalCartons = packingOrders.fold<int>(0, (a, o) => a + o.cartonCount);
    final totalWeight = packingOrders.fold<double>(0.0, (a, o) => a + o.totalNetWeight);
    final itemsTotalQty = shipmentItems.fold<int>(0, (a, i) => a + (int.tryParse(i['quantity']?.toString() ?? '0') ?? 0));
    final itemsTotalWt = shipmentItems.fold<double>(0.0, (a, i) => a + (double.tryParse(i['weight_per_carton']?.toString() ?? '0') ?? 0));

    final recipeTotalCost = recipes.fold<double>(0.0, (a, r) => a + r.totalCost);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape.copyWith(
            marginTop: 12, marginBottom: 12, marginLeft: 16, marginRight: 16,
          ),
          theme: pw.ThemeData.withFont(
            base: fontBase, bold: fontBold_, italic: fontBase, boldItalic: fontBold_,
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(s, grandTotal),
                pw.SizedBox(height: 6),
                _buildInfoSection(s),
                pw.SizedBox(height: 6),
                if (shipmentItems.isNotEmpty) ...[
                  _buildSectionTitle('بيان المنتجات المصدرة'),
                  pw.SizedBox(height: 4),
                  _buildShipmentItemsTable(shipmentItems, itemsTotalQty, itemsTotalWt),
                  pw.SizedBox(height: 6),
                ],
                if (packingOrders.isNotEmpty) ...[
                  _buildSectionTitle('ملخص التعبئة'),
                  pw.SizedBox(height: 4),
                  _buildPackingTable(packingOrders, totalCartons, totalWeight),
                  pw.SizedBox(height: 6),
                ],
                _buildSectionTitle('بيان المصروفات'),
                pw.SizedBox(height: 4),
                _buildExpensesTable(breakdown, settlements, costItems, useBreakdown, s.currencyCode),
                pw.SizedBox(height: 6),
                if (recipes.isNotEmpty && totalCartons > 0) ...[
                  _buildSectionTitle('المواد المستهلكة (وصفات التعبئة)'),
                  pw.SizedBox(height: 4),
                  _buildRecipeTable(recipes, totalCartons, recipeTotalCost),
                  pw.SizedBox(height: 6),
                ],
                _buildFinancialSummary(grandTotal, revenue, netProfit, margin, roi,
                    totalSupplierAmount, totalPackingCost, totalLogisticsCost, totalAdminCost, recipeTotalCost, s.currencyCode),
                pw.SizedBox(height: 8),
                _buildSignatureArea(),
              ],
            ),
          );
        },
      ),
    );
    return doc;
  }

  static pw.Widget _buildHeader(ExportShipmentModel s, double grandTotal) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 1.5, color: PdfColors.green700)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('فاتورة مركز التحضير',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
              pw.Text('Preparation Center Invoice',
                  style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            ],
          ),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.green700,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('مركز التحضير',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text('${AppUtils.formatNumber(grandTotal)} ${AppUtils.currencySymbol(s.currencyCode)}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.Text('إجمالي التكاليف',
                    style: pw.TextStyle(fontSize: 6, color: PdfColors.green200)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoSection(ExportShipmentModel s) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(children: [
        pw.Expanded(child: _infoChip('التاريخ', s.shipmentDate != null ? _fmtDate(s.shipmentDate!) : '—')),
        pw.Expanded(child: _infoChip('رقم الشحنة', s.shipmentNo)),
        pw.Expanded(child: _infoChip('اسم العميل', s.customerName ?? '—')),
      ]),
    );
  }

  static pw.Widget _infoChip(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: const pw.BoxDecoration(
        color: PdfColors.green700,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(title,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  static pw.Widget _buildShipmentItemsTable(List<Map<String, dynamic>> items, int totalQty, double totalWt) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        _headerRow(['المنتج', 'البيان', 'الكمية', 'الوزن']),
        ...items.map((item) => _dataRow([
              item['product_name']?.toString() ?? '—',
              'عدد كرتون الخدمة الفعلي',
              '${item['quantity'] ?? 0}',
              '${_d(item['weight_per_carton'])} كجم',
            ])),
        _totalRow4('الإجمالي', '', '$totalQty', '${totalWt.toStringAsFixed(1)} كجم'),
      ],
    );
  }

  static pw.TableRow _totalRow4(String l1, String v1, String v2, String v3) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        _tableCell(l1, bold: true), _tableCell(v1), _tableCell(v2, bold: true), _tableCell(v3, bold: true),
      ],
    );
  }

  static pw.Widget _buildPackingTable(List<PackingOrderModel> orders, int totalCartons, double totalWeight) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(0.8),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1),
      },
      children: [
        _headerRow(['المنتج', 'الدرجة', 'عدد الكراتين', 'الوزن الصافي', 'الوزن الإجمالي']),
        ...orders.map((o) => _dataRow([
              o.productName ?? '—',
              o.grade,
              '${o.cartonCount}',
              '${o.totalNetWeight.toStringAsFixed(1)}',
              '${o.totalGrossWeight.toStringAsFixed(1)}',
            ])),
        _totalRow5('الإجمالي', '$totalCartons', '${totalWeight.toStringAsFixed(1)} كجم', ''),
      ],
    );
  }

  static pw.Widget _buildExpensesTable(
    PrepCenterBreakdownResult breakdown,
    List<SupplierSettlementModel> settlements,
    List<PrepCenterCostItemModel> costItems,
    bool useBreakdown,
    String currencyCode,
  ) {
    if (useBreakdown) {
      final items = breakdown.allItems;
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(0.8),
          3: const pw.FlexColumnWidth(0.8),
          4: const pw.FlexColumnWidth(1),
          5: const pw.FlexColumnWidth(1.2),
          6: const pw.FlexColumnWidth(0.8),
          7: const pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow(['المنتج', 'البيان', 'الكمية', 'السعر', 'القيمة', 'اسم المورد', 'الفرز', 'ملاحظات']),
          ...items.map((item) {
            PdfColor? rowColor;
            if (breakdown.supplierItems.contains(item)) {
              rowColor = PdfColors.green50;
            } else if (breakdown.packingItems.contains(item)) {
              rowColor = PdfColors.blue50;
            } else if (breakdown.logisticsItems.contains(item)) {
              rowColor = PdfColors.orange50;
            } else {
              rowColor = PdfColors.purple50;
            }
            return _dataRow([
              item.description,
              item.categoryLabel,
              '${item.quantity.toStringAsFixed(1)} ${item.unitLabel}',
              '${item.unitCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
              '${item.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
              item.supplier ?? '—',
              item.costCategory.isNotEmpty ? item.costCategory : '—',
              item.notes ?? '—',
            ], color: rowColor);
          }),
        ],
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(1.2),
        6: const pw.FlexColumnWidth(0.8),
      },
      children: [
        _headerRow(['البيان', 'النوع', 'الكمية', 'السعر', 'القيمة', 'المورد', 'ملاحظات']),
        ...settlements.map((r) => _dataRow([
              r.productName ?? '—',
              r.grade,
              '${r.weightKg.toStringAsFixed(1)} كجم',
              '${r.unitPrice.toStringAsFixed(2)}',
              '${r.totalAmount.toStringAsFixed(2)}',
              r.supplierName ?? '—',
              r.notes ?? '—',
            ])),
        ...costItems.map((c) => _dataRow([
              c.description.isNotEmpty ? c.description : c.costTypeLabel,
              c.costTypeLabel,
              c.qty.toStringAsFixed(1),
              '${c.unitPrice.toStringAsFixed(2)}',
              '${c.totalCost.toStringAsFixed(2)}',
              '—',
              c.notes ?? '—',
            ])),
      ],
    );
  }

  static pw.Widget _buildRecipeTable(List<ShipmentRecipeSnapshotModel> recipes, int totalCartons, double totalCost) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(0.6),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(0.6),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(1),
        6: const pw.FlexColumnWidth(1),
      },
      children: [
        _headerRow(['المادة', 'الوحدة', 'لكل كرتونة', 'سعر الوحدة', 'الإجمالي', 'التكلفة']),
        ...recipes.map((r) => _dataRow([
          r.materialName ?? '—',
          r.unit ?? '—',
          r.quantityPerCarton.toStringAsFixed(2),
          r.unitCost > 0 ? '${r.unitCost.toStringAsFixed(2)}' : '—',
          '${r.totalQuantity.toStringAsFixed(1)} ${r.unit ?? ''}',
          r.unitCost > 0 ? '${r.totalCost.toStringAsFixed(2)}' : '—',
        ])),
        _totalRow6('الإجمالي', '', '', '', '', totalCost > 0 ? '${totalCost.toStringAsFixed(2)}' : '—'),
      ],
    );
  }

  static pw.Widget _buildFinancialSummary(
    double grandTotal, double revenue, double netProfit, double margin, double roi,
    double supplierAmount, double packingCost, double logisticsCost, double adminCost, double recipeCost,
    String currencyCode,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Text('ملخص مالي', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
            pw.Spacer(),
            if (grandTotal > 0)
              pw.Text('ROI: ${roi.toStringAsFixed(1)}%',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                      color: roi >= 0 ? PdfColors.green700 : PdfColors.red700)),
          ]),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            pw.Expanded(child: _finRow('تكلفة الخامة (الموردين)', supplierAmount, PdfColors.teal700, currencyCode: currencyCode)),
            pw.Expanded(child: _finRow('تكلفة التعبئة', packingCost, PdfColors.blue700, currencyCode: currencyCode)),
            pw.Expanded(child: _finRow('تكاليف لوجستية', logisticsCost, PdfColors.orange700, currencyCode: currencyCode)),
          ]),
          pw.Row(children: [
            pw.Expanded(child: _finRow('مصروفات إدارية', adminCost, PdfColors.purple700, currencyCode: currencyCode)),
            pw.Expanded(child: _finRow('إجمالي التكلفة', grandTotal, PdfColors.red700, bold: true, currencyCode: currencyCode)),
            pw.Expanded(child: _finRow('إجمالي الإيراد', revenue, PdfColors.green700, bold: true, currencyCode: currencyCode)),
          ]),
          pw.Row(children: [
            pw.Expanded(child: _finRow('صافي الربح', netProfit, netProfit >= 0 ? PdfColors.green700 : PdfColors.red700, bold: true, currencyCode: currencyCode)),
            pw.Expanded(child: _finRowPercent('هامش الربح', margin, PdfColors.black)),
            pw.Expanded(child: pw.SizedBox()),
          ]),
          pw.Divider(height: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 3),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly, children: [
            _finTag('الخامة', supplierAmount, PdfColors.teal700, currencyCode: currencyCode),
            _finTag('التعبئة', packingCost, PdfColors.blue700, currencyCode: currencyCode),
            _finTag('لوجستيات', logisticsCost, PdfColors.orange700, currencyCode: currencyCode),
            _finTag('إداري', adminCost, PdfColors.purple700, currencyCode: currencyCode),
            _finTag('إجمالي التكلفة', grandTotal, PdfColors.red700, currencyCode: currencyCode),
            _finTag('الإيراد', revenue, PdfColors.green700, currencyCode: currencyCode),
            _finTag('الربح', netProfit, netProfit >= 0 ? PdfColors.green700 : PdfColors.red700, currencyCode: currencyCode),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _finRow(String label, double amount, PdfColor color, {bool bold = false, String currencyCode = 'EGP'}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 2),
        pw.Text('${AppUtils.formatNumber(amount)} ${AppUtils.currencySymbol(currencyCode)}',
            style: pw.TextStyle(fontSize: 7, color: color, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ]),
    );
  }

  static pw.Widget _finRowPercent(String label, double value, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 2),
        pw.Text('${value.toStringAsFixed(2)}%',
            style: pw.TextStyle(fontSize: 7, color: color, fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  static pw.Widget _finTag(String label, double amount, PdfColor color, {String currencyCode = 'EGP'}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
          pw.Text('${AppUtils.formatNumber(amount)} ${AppUtils.currencySymbol(currencyCode)}',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureArea() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        pw.Column(children: [
          pw.Text('______________________', style: const pw.TextStyle(fontSize: 7)),
          pw.Text('توقيع مدير المركز', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ]),
        pw.Column(children: [
          pw.Text('______________________', style: const pw.TextStyle(fontSize: 7)),
          pw.Text('توقيع المحاسب', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ]),
        pw.Column(children: [
          pw.Text('______________________', style: const pw.TextStyle(fontSize: 7)),
          pw.Text('الختم', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ]),
      ],
    );
  }

  static pw.TableRow _headerRow(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: cells.map((c) => _tableHeader(c)).toList(),
    );
  }

  static pw.TableRow _dataRow(List<String> cells, {PdfColor? color}) {
    return pw.TableRow(
      decoration: color != null ? pw.BoxDecoration(color: color) : null,
      children: cells.map((c) => _tableCell(c)).toList(),
    );
  }

  static pw.TableRow _totalRow5(String label, String v1, String v2, String v3) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        _tableCell(label, bold: true), _tableCell(''), _tableCell(v1, bold: true), _tableCell(v2, bold: true), _tableCell(v3, bold: true),
      ],
    );
  }

  static pw.TableRow _totalRow6(String l1, String v1, String v2, String v3, String v4, String v5) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        _tableCell(l1, bold: true), _tableCell(v1), _tableCell(v2, bold: true), _tableCell(v3, bold: true), _tableCell(v4), _tableCell(v5, bold: true),
      ],
    );
  }

  static pw.Widget _tableHeader(String t) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
      alignment: pw.Alignment.center,
      child: pw.Text(t, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _tableCell(String t, {bool bold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5, horizontal: 2),
      alignment: pw.Alignment.center,
      child: pw.Text(t, style: pw.TextStyle(fontSize: 6, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal), textAlign: pw.TextAlign.center),
    );
  }

  static String _d(dynamic v) {
    if (v == null) return '0.00';
    if (v is double) return v.toStringAsFixed(2);
    if (v is num) return v.toDouble().toStringAsFixed(2);
    final parsed = double.tryParse(v.toString());
    return parsed?.toStringAsFixed(2) ?? '0.00';
  }

  static String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day}-${m[dt.month - 1]}-${dt.year}';
  }
}
