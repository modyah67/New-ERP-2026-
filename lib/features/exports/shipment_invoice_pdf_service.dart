import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shipment_cost_breakdown_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ShipmentInvoicePdfService {
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static Future<void> savePdf({
    required BuildContext context,
    required ExportShipmentModel shipment,
    required List<ShipmentCostBreakdownModel> breakdown,
    List<Map<String, dynamic>> itemsData = const [],
  }) async {
    final doc = await _generate(shipment, breakdown, itemsData);
    final bytes = await doc.save();
    
    final dir = await FileHelper.getExportDirectory();
    final safeName = shipment.shipmentNo.replaceAll(RegExp(r'[\\/]'), '_');
    final fileName = 'Invoice_$safeName.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الفاتورة في:\n${file.path}'),
          backgroundColor: const Color(0xFF00C853),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  static Future<void> previewPdf({
    required BuildContext context,
    required ExportShipmentModel shipment,
    required List<ShipmentCostBreakdownModel> breakdown,
    List<Map<String, dynamic>> itemsData = const [],
  }) async {
    final doc = await _generate(shipment, breakdown, itemsData);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static Future<pw.Document> _generate(
    ExportShipmentModel s,
    List<ShipmentCostBreakdownModel> breakdown,
    List<Map<String, dynamic>> itemsData,
  ) async {
    final doc = pw.Document();
    late final pw.Font fontBase;
    late final pw.Font fontBold_;
    pw.MemoryImage? bgImage;
    try {
      bgImage = pw.MemoryImage(
        (await rootBundle.load('assets/images/statment.png')).buffer.asUint8List(),
      );
    } catch (_) {}
    try {
      final fr = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fb = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      fontBase = pw.Font.ttf(fr);
      fontBold_ = pw.Font.ttf(fb);
    } catch (_) {
      fontBase = pw.Font.helvetica();
      fontBold_ = pw.Font.helveticaBold();
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          _pageW,
          _pageH,
          marginTop: 20,
          marginBottom: 20,
          marginLeft: 24,
          marginRight: 24,
        ),
        theme: pw.ThemeData.withFont(
          base: fontBase,
          bold: fontBold_,
          italic: fontBase,
          boldItalic: fontBold_,
        ),
        build: (pw.Context context) {
          return pw.Stack(children: [
            if (bgImage != null) pw.Positioned.fill(child: pw.Image(bgImage, fit: pw.BoxFit.fill)),
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildHeader(s),
                  pw.SizedBox(height: 12),
                  _buildShipmentInfo(s),
                  pw.SizedBox(height: 16),
                  _buildExportedProductsSection(itemsData, s.cartonsCount),
                  pw.SizedBox(height: 12),
                  _buildRawMaterialsSection(breakdown, s.currencyCode),
                  pw.SizedBox(height: 12),
                  _buildOperationsSection(breakdown, s.currencyCode),
                  pw.SizedBox(height: 16),
                  _buildFinancialSummary(breakdown, s),
                  pw.SizedBox(height: 12),
                  _buildSupplierTags(breakdown),
                ],
              ),
            ),
          ]);
        },
      ),
    );
    return doc;
  }

  // ── Header ──

  static pw.Widget _buildHeader(ExportShipmentModel s) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('فاتورة تكاليف التصدير',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(
                'Fruity Farms — Egypt',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(s.shipmentNo,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Shipment Info ──

  static pw.Widget _buildShipmentInfo(ExportShipmentModel s) {
    final dateStr = _formatDate(s.shipmentDate);
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _infoRow2('العميل', s.customerName ?? '—', 'التاريخ', dateStr),
          pw.SizedBox(height: 3),
          _infoRow2(
              'الحاوية', s.containerNo ?? '—', 'الوجهة', s.country ?? '—'),
          pw.SizedBox(height: 3),
          _infoRow2('عدد الكراتين', '${s.cartonsCount}', 'الوزن الصافي',
              '${s.netWeight} كجم'),
        ],
      ),
    );
  }

  static pw.Widget _infoRow2(
      String l1, String v1, String l2, String v2) {
    return pw.Row(children: [
      pw.Text(l1,
          style: pw.TextStyle(
              fontSize: 8, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(width: 4),
      pw.Text(v1, style: const pw.TextStyle(fontSize: 8)),
      pw.SizedBox(width: 24),
      pw.Text(l2,
          style: pw.TextStyle(
              fontSize: 8, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(width: 4),
      pw.Text(v2, style: const pw.TextStyle(fontSize: 8)),
    ]);
  }

  // ── Section 1: Exported Products ──

  static pw.Widget _buildExportedProductsSection(
      List<Map<String, dynamic>> items, int totalCartons) {
    if (items.isEmpty) return pw.SizedBox();
    final totalQty = items.fold<int>(0, (s, i) => s + (int.tryParse(i['quantity']?.toString() ?? '0') ?? 0));

    return pw.Column(children: [
      _buildSectionTitle('المنتجات المُصدَّرة', PdfColors.green700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(1.2),
        },
        children: [
          _headerRow(['المنتج', 'عدد الكراتين', 'الوزن (كجم)']),
          ...items.map((item) {
            final productName = item['product_name']?.toString() ?? item['name']?.toString() ?? '—';
            final qty = item['quantity']?.toString() ?? '0';
            final wt = item['weight_per_carton']?.toString() ?? item['weightPerCarton']?.toString() ?? '—';
            return _dataRow([productName, qty, wt != '—' ? '$wt كجم' : '—']);
          }),
          _totalRowCol3('الإجمالي', '$totalQty', '', boldTotal: true),
        ],
      ),
    ]);
  }

  // ── Section 2: Raw Materials ──

  static pw.Widget _buildRawMaterialsSection(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final items = b.where((r) => r.costType == 'fruit').toList();
    if (items.isEmpty) return pw.SizedBox();
    final total = items.fold<double>(0.0, (s, r) => s + r.totalCost);

    return pw.Column(children: [
      _buildSectionTitle('الخامات', PdfColors.green700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1),
          4: const pw.FlexColumnWidth(1.5),
        },
        children: [
          _headerRow(['المنتج', 'الكمية', 'السعر', 'القيمة', 'المورد']),
          ...items.map((r) => _dataRow([
                r.itemName,
                '${r.quantity.toStringAsFixed(1)} كجم',
                '${r.unitCost.toStringAsFixed(2)}',
                '${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
                r.supplier ?? '—',
              ])),
          _totalRowCol('الإجمالي', '${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}'),
        ],
      ),
    ]);
  }

  // ── Section 3: Operations & Expenses ──

  static pw.Widget _buildOperationsSection(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final types = ['packing_material', 'logistics', 'export_cost', 'admin', 'other'];
    final items = b.where((r) => types.contains(r.costType)).toList();
    if (items.isEmpty) return pw.SizedBox();
    final total = items.fold<double>(0.0, (s, r) => s + r.totalCost);

    return pw.Column(children: [
      _buildSectionTitle('مصروفات التشغيل والتعبئة والنقل', PdfColors.blue700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow(['البيان', 'الكمية', 'القيمة']),
          ...items.map((r) => _dataRow([
                r.itemName,
                r.quantity > 0 ? r.quantity.toStringAsFixed(1) : '',
                '${r.totalCost.toStringAsFixed(2)} ${r.currency}',
              ])),
          _totalRowCol('الإجمالي', '${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}'),
        ],
      ),
    ]);
  }

  // ── Section 4: Financial Summary ──

  static pw.Widget _buildFinancialSummary(
      List<ShipmentCostBreakdownModel> b, ExportShipmentModel s) {
    final fruitTotal = _typeSum(b, 'fruit');
    final types = ['packing_material', 'logistics', 'export_cost', 'admin', 'other'];
    final opTotal = b.where((r) => types.contains(r.costType))
        .fold<double>(0.0, (sum, r) => sum + r.totalCost);
    final grandTotal = fruitTotal + opTotal;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('الملخص المالي',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _summaryRow('إجمالي الخام',
              '${fruitTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}'),
          pw.Divider(height: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 3),
          _summaryRow('إجمالي المصروفات',
              '${opTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}'),
          pw.Divider(height: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 3),
          _summaryRow('إجمالي تكلفة الشحنة',
              '${grandTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}',
              bold: true),
        ],
      ),
    );
  }

  // ── Section 5: Supplier Tags ──

  static pw.Widget _buildSupplierTags(List<ShipmentCostBreakdownModel> b) {
    final suppliers = b
        .where((r) => r.supplier != null && r.supplier!.trim().isNotEmpty)
        .map((r) => r.supplier!)
        .toSet()
        .toList();
    if (suppliers.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('الموردون: ',
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Wrap(
          spacing: 6,
          runSpacing: 4,
          children: suppliers.map((s) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Text(s,
                style: const pw.TextStyle(fontSize: 7)),
          )).toList(),
        ),
      ],
    );
  }

  // ── Utilities ──

  static pw.Widget _buildSectionTitle(String title, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white)),
    );
  }

  static double _typeSum(
          List<ShipmentCostBreakdownModel> b, String type) =>
      b.where((r) => r.costType == type)
          .fold<double>(0.0, (s, r) => s + r.totalCost);

  static pw.TableRow _headerRow(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: cells
          .map((c) => _tableHeader(c))
          .toList(),
    );
  }

  static pw.TableRow _dataRow(List<String> cells) {
    return pw.TableRow(
      children: cells
          .map((c) => _tableCell(c))
          .toList(),
    );
  }

  static pw.TableRow _totalRowCol(String label, String value) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.blue50),
      children: [
        _tableCell(label, bold: true),
        _tableCell(''),
        _tableCell(value, bold: true),
      ],
    );
  }

  static pw.TableRow _totalRowCol3(String label, String value, String empty,
      {bool boldTotal = false}) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        _tableCell(label, bold: boldTotal),
        _tableCell(value, bold: boldTotal),
        _tableCell(empty),
      ],
    );
  }

  static pw.Widget _tableHeader(String t) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(t,
          style: pw.TextStyle(
              fontSize: 7, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _tableCell(String t,
      {bool bold = false, pw.Alignment? alignment}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      alignment: alignment ?? pw.Alignment.center,
      child: pw.Text(t,
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _summaryRow(String label, String value,
      {bool bold = false}) {
    return pw.Row(children: [
      pw.Text(label,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold)),
      pw.Spacer(),
      pw.Text(value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          )),
    ]);
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day}-${m[dt.month - 1]}-${dt.year}';
  }
}
