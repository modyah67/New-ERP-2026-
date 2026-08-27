import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class PackingOrderPdfService {
  static Future<String> savePdf({
    required String warehouseName,
    required List<Map<String, dynamic>> lotEntries,
    required List<Map<String, dynamic>> materialItems,
    required List<Map<String, dynamic>> costItems,
    required double totalFruitCostBeforeWaste,
    required double totalWasteCost,
    required double totalFruitCostAfterWaste,
    required double totalMaterialCost,
    required double totalMaterialWasteCost,
    required double totalCostItems,
    required double totalAll,
    required double packingCostPerCarton,
    String currency = 'EGP',
  }) async {
    final doc = await _generate(
      warehouseName: warehouseName,
      lotEntries: lotEntries,
      materialItems: materialItems,
      costItems: costItems,
      totalFruitCostBeforeWaste: totalFruitCostBeforeWaste,
      totalWasteCost: totalWasteCost,
      totalFruitCostAfterWaste: totalFruitCostAfterWaste,
      totalMaterialCost: totalMaterialCost,
      totalMaterialWasteCost: totalMaterialWasteCost,
      totalCostItems: totalCostItems,
      totalAll: totalAll,
      packingCostPerCarton: packingCostPerCarton,
      currency: currency,
    );
    final bytes = await doc.save();
    final dir = await FileHelper.getExportDirectory();
    final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final file = File('${dir.path}/packing_order_$timestamp.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> printPdf({
    required String warehouseName,
    required List<Map<String, dynamic>> lotEntries,
    required List<Map<String, dynamic>> materialItems,
    required List<Map<String, dynamic>> costItems,
    required double totalFruitCostBeforeWaste,
    required double totalWasteCost,
    required double totalFruitCostAfterWaste,
    required double totalMaterialCost,
    required double totalMaterialWasteCost,
    required double totalCostItems,
    required double totalAll,
    required double packingCostPerCarton,
    String currency = 'EGP',
  }) async {
    final doc = await _generate(
      warehouseName: warehouseName,
      lotEntries: lotEntries,
      materialItems: materialItems,
      costItems: costItems,
      totalFruitCostBeforeWaste: totalFruitCostBeforeWaste,
      totalWasteCost: totalWasteCost,
      totalFruitCostAfterWaste: totalFruitCostAfterWaste,
      totalMaterialCost: totalMaterialCost,
      totalMaterialWasteCost: totalMaterialWasteCost,
      totalCostItems: totalCostItems,
      totalAll: totalAll,
      packingCostPerCarton: packingCostPerCarton,
      currency: currency,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
    );
  }

  static Future<pw.Document> _generate({
    required String warehouseName,
    required List<Map<String, dynamic>> lotEntries,
    required List<Map<String, dynamic>> materialItems,
    required List<Map<String, dynamic>> costItems,
    required double totalFruitCostBeforeWaste,
    required double totalWasteCost,
    required double totalFruitCostAfterWaste,
    required double totalMaterialCost,
    required double totalMaterialWasteCost,
    required double totalCostItems,
    required double totalAll,
    required double packingCostPerCarton,
    String currency = 'EGP',
  }) async {
    final doc = pw.Document();
    final fontRegular =
        await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final fontBold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final font = pw.Font.ttf(fontRegular);
    final fontBold_ = pw.Font.ttf(fontBold);

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final isCartonMode = lotEntries.any((e) => e['is_carton_mode'] == true);
    final weightUnit = isCartonMode ? 'كرتونة' : 'كجم';
    final costUnitLabel = isCartonMode ? 'تكلفة الكرتونة' : 'تكلفة الوحدة';

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold_,
            italic: font,
            boldItalic: fontBold_,
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context context) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildHeader(dateStr),
                  pw.SizedBox(height: 16),
                  _buildWarehouseInfo(warehouseName, dateStr, isCartonMode),
                  pw.SizedBox(height: 16),
                  ..._buildLotEntries(lotEntries, currency, weightUnit),
                  pw.SizedBox(height: 12),
                  _buildMaterialsSection(materialItems, currency),
                  pw.SizedBox(height: 12),
                  _buildCostItemsSection(costItems, currency),
                  pw.SizedBox(height: 12),
                  _buildCostSummary(
                    totalFruitCostBeforeWaste: totalFruitCostBeforeWaste,
                    totalWasteCost: totalWasteCost,
                    totalFruitCostAfterWaste: totalFruitCostAfterWaste,
                    totalMaterialCost: totalMaterialCost,
                    totalMaterialWasteCost: totalMaterialWasteCost,
                    totalCostItems: totalCostItems,
                    totalAll: totalAll,
                    packingCostPerCarton: packingCostPerCarton,
                    currency: currency,
                    costUnitLabel: costUnitLabel,
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );
    return doc;
  }

  static pw.Widget _buildHeader(String dateStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'FRUITY FARMS',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 20),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: 1),
              top: pw.BorderSide(width: 1),
            ),
          ),
          child: pw.Text(
            ' أمر التعبئة ',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '===================================',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
        ),
      ],
    );
  }

  static pw.Widget _buildWarehouseInfo(String warehouseName, String dateStr, bool isCartonMode) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _infoRowPdf('المخزن:', warehouseName),
          pw.SizedBox(height: 4),
          _infoRowPdf('تاريخ الإنشاء:', dateStr),
          pw.SizedBox(height: 4),
          _infoRowPdf('الوضع:', isCartonMode ? 'كراتين (كرتونة)' : 'أوزان (كجم)'),
        ],
      ),
    );
  }

  static pw.Widget _weightLabel(String label, double value, String unit) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 160,
          child: pw.Text(label,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.right),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(
            '${value.toStringAsFixed(1)} $unit',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  static List<pw.Widget> _buildLotEntries(List<Map<String, dynamic>> entries, String currency, String weightUnit) {
    final widgets = <pw.Widget>[];
    widgets.add(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 1)),
            ),
            child: pw.Text(
              '-----------------------------------',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ),
          pw.Text(
            'المحاصيل:',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 1)),
            ),
            child: pw.Text(
              '-----------------------------------',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ),
        ],
      ),
    );

    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final wasteWeight = (e['waste_weight'] as double?) ?? 0;
      final sortedWeight = (e['sorted_weight'] as double?) ?? 0;
      final sortingCost = (e['sorting_cost'] as double?) ?? 0;
      final totalNetWeight = (e['total_net_weight'] as double?) ?? 0;
      final totalGrossWeight = (e['total_gross_weight'] as double?) ?? 0;
      final isCarton = e['is_carton_mode'] == true;
      final unit = isCarton ? 'كرتونة' : 'كجم';

      widgets.add(pw.SizedBox(height: 8));
      widgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'المحصول #${i + 1}:',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              _detailRow('المنتج', '${e['product_name']}'),
              _detailRow('رقم اللوت', '${e['lot_number']}'),
              _detailRow('المورد', '${e['supplier_name']}'),
              if (isCarton)
                _detailRow('الوزن الإجمالي',
                    '${(e['gross_weight'] as double).toStringAsFixed(1)} كجم'),
              _weightLabel(isCarton ? 'الكمية الإجمالية' : 'الوزن الإجمالي',
                  (e['effective_weight'] as double), unit),
              if (wasteWeight > 0)
                _weightLabel('الهالك', wasteWeight, unit),
              _weightLabel(isCarton ? 'الصافي' : 'الوزن الصافي',
                  (e['net_weight'] as double), unit),
              if (sortedWeight > 0)
                _weightLabel('الفرز', sortedWeight, unit),
              _detailRow('عدد الكراتين', '${e['carton_count']}'),
              _detailRow('الكراتين الصافي', '${e['net_carton_count'] ?? e['carton_count']}'),
              _detailRow('الوزن الصافي للكرتونة',
                  '${(e['net_weight_per_carton'] as double).toStringAsFixed(1)} كجم'),
              if (isCarton)
                _detailRow('الوزن الإجمالي للكرتونة',
                    '${(e['gross_weight_per_carton'] as double?)?.toStringAsFixed(1) ?? "—"} كجم'),
              _detailRow('إجمالي الوزن الصافي',
                  '${totalNetWeight.toStringAsFixed(1)} كجم'),
              _detailRow('إجمالي الوزن الإجمالي',
                  '${totalGrossWeight.toStringAsFixed(1)} كجم'),
              pw.SizedBox(height: 4),
              _detailRow('تكلفة الفاكهة',
                  '${(e['total_purchase_cost'] as double).toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
              _detailRow('تكلفة الكرتونة',
                  '${(e['cost_per_carton'] as double? ?? e['cost_per_unit'] as double? ?? 0).toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
              if (sortingCost > 0)
                _detailRow('تكلفة الفرز',
                    '${sortingCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
              _detailRow('تكلفة الفاكهة (صافي)',
                  '${(e['fruit_cost'] as double).toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  static pw.Widget _buildMaterialsSection(List<Map<String, dynamic>> items, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1)),
          ),
          child: pw.Text(
            '-----------------------------------',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
        pw.Text(
          'مواد التعبئة:',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1)),
          ),
          child: pw.Text(
            '-----------------------------------',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
        pw.SizedBox(height: 8),
        if (items.isEmpty)
          pw.Text('—', style: const pw.TextStyle(fontSize: 10)),
        ...items.map((item) {
          final used = ((item['used_qty'] ?? 0) as num).toDouble();
          final unitCost = ((item['unit_cost'] ?? 0) as num).toDouble();
          final total = used * unitCost;
          final origCurrency = (item['currency'] as String?) ?? 'EGP';
          final exchangeRate = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          final unitCostEgp = (item['unit_cost'] as double?) ?? 0;
          final unitCostOrig = exchangeRate > 1 ? unitCostEgp / exchangeRate : unitCostEgp;
          final currencySuffix = origCurrency != 'EGP'
              ? ' ($origCurrency ${unitCostOrig.toStringAsFixed(2)} × ${exchangeRate.toStringAsFixed(2)})'
              : '';
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              '${item['product_name']} | الكمية: ${(item['used_qty'] as double).toStringAsFixed(1)} | الوحدة: ${unitCostEgp.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}$currencySuffix | الإجمالي: ${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          );
        }),
        if (items.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 0.5)),
            ),
            child: pw.Text(
              'إجمالي مواد التعبئة: ${items.fold<double>(0, (s, i) => s + (((i['used_qty'] ?? 0) as num).toDouble() * ((i['unit_cost'] ?? 0) as num).toDouble())).toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildCostItemsSection(List<Map<String, dynamic>> items, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1)),
          ),
          child: pw.Text(
            '-----------------------------------',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
        pw.Text(
          'بنود التكلفة:',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1)),
          ),
          child: pw.Text(
            '-----------------------------------',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
        pw.SizedBox(height: 8),
        if (items.isEmpty)
          pw.Text('—', style: const pw.TextStyle(fontSize: 10)),
        ...items.map((item) {
          final total = (item['total'] as double?) ?? 0;
          final origCurrency = (item['supplier_currency'] as String?) ?? 'EGP';
          final exchangeRate = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          final unitPrice = (item['unit_price'] as double?) ?? 0;
          final unitPriceOrig = exchangeRate > 1 ? unitPrice / exchangeRate : unitPrice;
          final currencySuffix = origCurrency != 'EGP'
              ? ' ($origCurrency ${unitPriceOrig.toStringAsFixed(2)} × ${exchangeRate.toStringAsFixed(2)})'
              : '';
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              '${item['name']} | المورد: ${item['supplier_name'] ?? ''} | الكمية: ${(item['quantity'] as double).toStringAsFixed(1)} | الوحدة: ${unitPrice.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}$currencySuffix | الإجمالي: ${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          );
        }),
        if (items.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 0.5)),
            ),
            child: pw.Text(
              'إجمالي بنود التكلفة: ${items.fold<double>(0, (s, i) => s + ((i['total'] as double?) ?? 0)).toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildCostSummary({
    required double totalFruitCostBeforeWaste,
    required double totalWasteCost,
    required double totalFruitCostAfterWaste,
    required double totalMaterialCost,
    required double totalMaterialWasteCost,
    required double totalCostItems,
    required double totalAll,
    required double packingCostPerCarton,
    required String currency,
    String costUnitLabel = 'تكلفة الكرتونة',
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('===================================',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 4),
          pw.Text(
            'ملخص التكاليف:',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            child: pw.Text(
              '-----------------------------------',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ),
          pw.SizedBox(height: 6),
          _summaryRowPdf(
              'تكلفة الفاكهة (قبل الهالك والفرز)',
              '${totalFruitCostBeforeWaste.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
          if (totalWasteCost > 0) ...[
            pw.SizedBox(height: 3),
            _summaryRowPdf(
                '+ تكلفة الهالك', '${totalWasteCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
          ],
          if (totalFruitCostAfterWaste != totalFruitCostBeforeWaste) ...[
            pw.SizedBox(height: 3),
            _summaryRowPdf(
                'تكلفة الفاكهة (بعد الهالك والفرز)',
                '${totalFruitCostAfterWaste.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
          ],
          pw.SizedBox(height: 3),
          _summaryRowPdf('إجمالي مواد التعبئة',
              '${totalMaterialCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
          if (totalMaterialWasteCost > 0) ...[
            pw.SizedBox(height: 3),
            _summaryRowPdf('فقد مواد التعبئة',
                '${totalMaterialWasteCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
          ],
          pw.SizedBox(height: 3),
          _summaryRowPdf('إجمالي بنود التكلفة',
              '${totalCostItems.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}'),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 1)),
            ),
            child: pw.Text(
              '-----------------------------------',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ),
          pw.SizedBox(height: 4),
          _summaryRowPdf(
            'التكلفة الإجمالية',
            '${totalAll.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}',
            bold: true,
          ),
          pw.SizedBox(height: 3),
          _summaryRowPdf(
            costUnitLabel,
            '${packingCostPerCarton.toStringAsFixed(2)} ${AppUtils.currencySymbol(currency)}',
            bold: true,
          ),
          pw.SizedBox(height: 4),
          pw.Text('===================================',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  static pw.Widget _infoRowPdf(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 8),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 160,
            child: pw.Text(label,
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.right),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRowPdf(String label, String value,
      {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            )),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            )),
      ],
    );
  }
}
