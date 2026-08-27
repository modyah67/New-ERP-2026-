import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart' show PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/dao/cost_report_dao.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:accounting_system/core/utils/file_helper.dart';

class CostDetailsReportPage extends StatefulWidget {
  final String? category;
  final String? categoryLabel;
  final int? shipmentId;
  final String? itemName;
  final String? majorCategory;
  const CostDetailsReportPage(
      {super.key,
      this.category,
      this.categoryLabel,
      this.shipmentId,
      this.itemName,
      this.majorCategory});

  @override
  State<CostDetailsReportPage> createState() => _CostDetailsReportPageState();
}

class _CostDetailsReportPageState extends State<CostDetailsReportPage> {
  final _dao = CostReportDao();
  bool _loading = true;
  bool _exportLoading = false;
  List<Map<String, dynamic>> _rows = [];
  String? _category;

  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  String _catLabel(String cat) {
    switch (cat) {
      case 'freight':
      case 'shipping_company':
      case 'shipping':
        return 'تكلفة شركات الشحن';
      case 'clearance':
      case 'clearing_agent':
      case 'clearing':
        return 'تكلفة المخلصين';
      case 'crop':
      case 'fruit':
      case 'manual_crop':
        return 'تكلفة المحاصيل';
      case 'packing_material':
        return 'مواد التعبئة';
      case 'packing':
      case 'PACKAGING':
      case 'manual_packing':
        return 'تعبئة وتغليف';
      case 'logistics':
      case 'TRANSPORT':
        return 'لوجستيك ونقل';
      case 'admin':
        return 'مصاريف إدارية';
      case 'export_cost':
        return 'تكاليف تصدير';
      case 'LABOR':
        return 'عمالة';
      case 'DIESEL':
        return 'ديزل';
      case 'AGRICULTURE':
        return 'أجرة زراعية';
      case 'COOLING':
        return 'تبريد';
      case 'LABELS':
        return 'ليبل';
      case 'STICKERS':
        return 'استيكر';
      case 'OTHER':
      case 'other':
        return 'أخرى';
      default:
        return cat;
    }
  }

  String _displayCategory(Map<String, dynamic> row) {
    final cat = (row['category'] as String?) ?? '';
    if (cat == 'other' || cat == 'OTHER') {
      return row['item_name']?.toString() ?? 'أخرى';
    }
    return _catLabel(cat);
  }

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _load();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  String _getMajorCategory(Map<String, dynamic> row) {
    final name = (row['item_name'] as String? ?? '').toLowerCase();
    final cat = (row['category'] as String? ?? '').trim();
    final catLower = cat.toLowerCase();

    if (cat == 'تكلفة شركات الشحن' ||
        catLower == 'shipping_company' ||
        catLower == 'freight' ||
        catLower == 'shipping' ||
        catLower == 'transport' ||
        name.contains('شحن')) {
      return 'تكلفة شركات الشحن';
    }
    if (cat == 'تكلفة المخلصين' ||
        catLower == 'clearing_agent' ||
        catLower == 'clearance' ||
        catLower == 'clearing' ||
        name.contains('تخليص') ||
        name.contains('مخلص')) {
      return 'تكلفة المخلصين';
    }
    if (cat == 'تكلفة المحاصيل' ||
        cat == 'المحاصيل' ||
        catLower == 'crop' ||
        catLower == 'manual_crop' ||
        name.contains('محصول')) {
      return 'تكلفة المحاصيل';
    }
    if (cat == 'مواد التعبئة' ||
        catLower == 'packing_material' ||
        name.contains('ورق') ||
        name.contains('كراتين')) {
      return 'مواد التعبئة';
    }
    if (cat == 'تعبئة وتغليف' ||
        catLower == 'packing' ||
        catLower == 'packaging' ||
        catLower == 'manual_packing' ||
        name.contains('تعبئة')) {
      return 'تعبئة وتغليف';
    }
    if (cat == 'مصاريف إدارية' || catLower == 'admin') return 'مصاريف إدارية';
    if (cat == 'لوجستيك ونقل' || catLower == 'logistics') return 'لوجستيك ونقل';
    if (catLower == 'general' || catLower == 'other' || cat.isEmpty) return 'أخرى';
    return cat;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = _fromCtrl.text.isNotEmpty ? _fromCtrl.text : null;
      final to = _toCtrl.text.isNotEmpty ? _toCtrl.text : null;

      final data = await _dao.getDetails(
        category: _category,
        shipmentId: widget.shipmentId,
        itemName: widget.itemName,
        fromDate: from,
        toDate: to,
      );

      if (mounted) {
        setState(() {
          if (widget.majorCategory != null) {
            _rows = data
                .where((r) => _getMajorCategory(r) == widget.majorCategory)
                .toList();
          } else {
            _rows = data;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary, surface: AppTheme.background),
        ),
        child: child!,
      ),
    );
    if (d != null) {
      ctrl.text =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.majorCategory != null
        ? widget.majorCategory!
        : widget.shipmentId != null
            ? (_rows.isNotEmpty
                ? (_rows.first['shipment_no']?.toString() ??
                    'الشحنة #${widget.shipmentId}')
                : 'الشحنة #${widget.shipmentId}')
            : widget.itemName != null
                ? widget.itemName!
                : widget.categoryLabel != null
                    ? widget.categoryLabel!
                    : _category != null
                        ? _catLabel(_category!)
                        : 'تفاصيل التكاليف';
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: AppTheme.backgroundGradient,
          child: Column(
            children: [
              _buildHeader(title),
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.primary))
                    : _buildTable(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _translateItemName(String item, bool isEnglish) {
    if (!isEnglish) return item;
    final lower = item.toLowerCase();

    // Fruits
    if (lower.contains('مانجا') || lower.contains('مانجو')) return 'Mango';
    if (lower.contains('فراولة')) return 'Strawberry';
    if (lower.contains('برتقال')) return 'Orange';
    if (lower.contains('عنب فليم')) return 'Flame Grapes';
    if (lower.contains('عنب ايرلي') ||
        lower.contains('عنب أيرلي') ||
        lower.contains('عنب ءايرلي') ||
        lower.contains('عنب إيرلي')) return 'Early Sweet Grapes';
    if (lower.contains('عنب')) return 'Grapes';
    if (lower.contains('رمان')) return 'Pomegranate';
    if (lower.contains('ليمون')) return 'Lemon';
    if (lower.contains('يوسفي') || lower.contains('مندرين')) return 'Mandarin';
    if (lower.contains('تفاح')) return 'Apple';
    if (lower.contains('موز')) return 'Banana';
    if (lower.contains('بطيخ')) return 'Watermelon';
    if (lower.contains('شمام') || lower.contains('كنتالوب'))
      return 'Cantaloupe / Melon';
    if (lower.contains('خوخ')) return 'Peach';
    if (lower.contains('مشمش')) return 'Apricot';
    if (lower.contains('برقوق')) return 'Plum';
    if (lower.contains('جوافة')) return 'Guava';
    if (lower.contains('بلح') || lower.contains('تمر')) return 'Dates';
    if (lower.contains('تين')) return 'Fig';
    if (lower.contains('كمثرى') || lower.contains('اجاص')) return 'Pear';
    if (lower.contains('كيوي')) return 'Kiwi';

    // Materials & Costs
    if (lower.contains('تعبئة') || lower.contains('تغليف'))
      return 'Packing & Packaging';
    if (lower.contains('كراتين') || lower.contains('كرتون')) return 'Cartons';
    if (lower.contains('بلاستيك') || lower.contains('أكياس'))
      return 'Plastic / Bags';
    if (lower.contains('شحن')) return 'Shipping';
    if (lower.contains('تخليص')) return 'Clearance';
    if (lower.contains('نولون') || lower.contains('نقل'))
      return 'Transport / Freight';
    if (lower.contains('عمالة') ||
        lower.contains('عامل') ||
        lower.contains('يومية')) return 'Labor';
    if (lower.contains('مصاريف') || lower.contains('إدارية'))
      return 'Administrative Expenses';
    if (lower.contains('ورق')) return 'Paper';
    if (lower.contains('خشب') ||
        lower.contains('بالتة') ||
        lower.contains('بالتات')) return 'Pallets';

    return item;
  }

  Future<void> _exportToExcel(bool isEnglish) async {
    if (_rows.isEmpty) return;
    setState(() => _exportLoading = true);
    try {
      var excel = Excel.createExcel();
      var sheet = excel[isEnglish ? 'Cost Details' : 'تفاصيل التكاليف'];
      excel.setDefaultSheet(sheet.sheetName);

      sheet.appendRow(isEnglish
          ? [
              TextCellValue('Date'),
              TextCellValue('Shipment No'),
              TextCellValue('Customer'),
              TextCellValue('Item'),
              TextCellValue('Quantity'),
              TextCellValue('Unit Price'),
              TextCellValue('Exchange Rate'),
              TextCellValue('Total in Currency'),
              TextCellValue('Total (EGP)'),
            ]
          : [
              TextCellValue('التاريخ'),
              TextCellValue('رقم الشحنة'),
              TextCellValue('العميل'),
              TextCellValue('البيان'),
              TextCellValue('الكمية'),
              TextCellValue('سعر الوحدة'),
              TextCellValue('سعر الصرف'),
              TextCellValue('الإجمالي بالعملة'),
              TextCellValue('الإجمالي بالمصري'),
            ]);

      double totalQty = 0;
      double totalAmount = 0;

      for (final r in _rows) {
        final date = r['shipment_date']?.toString() ?? '';
        final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
        final qty = double.tryParse(r['quantity']?.toString() ?? '0') ?? 0;
        final amount = double.tryParse(r['amount']?.toString() ?? '0') ?? 0;
        final exchangeRate =
            double.tryParse(r['exchange_rate']?.toString() ?? '1') ?? 1.0;
        final totalInCurrency = double.tryParse(
                r['total_in_currency']?.toString() ?? amount.toString()) ??
            amount;
        final currency = _getCurrencyName(r['currency']?.toString());

        final unitPriceForeign = qty > 0 ? totalInCurrency / qty : 0.0;

        totalQty += qty;
        totalAmount += amount;

        sheet.appendRow([
          TextCellValue(dateStr),
          TextCellValue('\u200E${r['shipment_no']?.toString() ?? ''}'),
          TextCellValue(r['customer_name']?.toString() ?? ''),
          TextCellValue(
              _translateItemName(r['item_name']?.toString() ?? '', isEnglish)),
          DoubleCellValue(qty),
          TextCellValue(
              '$currency ${unitPriceForeign.toStringAsFixed(2)}'),
          DoubleCellValue(exchangeRate),
          TextCellValue('$currency ${totalInCurrency.toStringAsFixed(2)}'),
          DoubleCellValue(amount),
        ]);
      }

      // Append Totals Row
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(isEnglish ? 'Total' : 'الإجمالي'),
        DoubleCellValue(totalQty),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(totalAmount),
      ]);

      final dir = await FileHelper.getExportDirectory();
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path = '${dir.path}/Cost_Details_$now.xlsx';
      final bytes = excel.save();
      if (bytes != null) {
        final file = File(path);
        await file.writeAsBytes(bytes);
        OpenFilex.open(path);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ في التصدير: $e')));
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _printReport() async {
    final totalAmount = _rows.fold<double>(
        0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final shipmentNo =
        _rows.isNotEmpty ? (_rows.first['shipment_no']?.toString() ?? '') : '';

    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(20),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          pw.Text(AppConstants.companyName,
              style: pw.TextStyle(
                  font: fontBold, fontSize: 16, color: PdfColors.blueGrey)),
          pw.Text('تفاصيل التكاليف',
              style: pw.TextStyle(
                  font: fontBold, fontSize: 14, color: PdfColors.black)),
          pw.SizedBox(height: 4),
          pw.Text('تاريخ التقرير: $now',
              style: pw.TextStyle(
                  font: font, fontSize: 10, color: PdfColors.grey700)),
          if (shipmentNo.isNotEmpty)
            pw.Text('رقم الشحنة: $shipmentNo',
                style: pw.TextStyle(
                    font: font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(
                font: fontBold, fontSize: 8, color: PdfColors.white),
            cellStyle:
                pw.TextStyle(font: font, fontSize: 7, color: PdfColors.black),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
            cellDecoration: (row, col, isHeader) => const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
            headers: [
              'التاريخ',
              'رقم الشحنة',
              'العميل',
              'البيان',
              'الكمية',
              'سعر الوحدة',
              'سعر الصرف',
              'الإجمالي بالعملة',
              'الإجمالي (EGP)'
            ],
            data: _rows.map((r) {
              final date = r['shipment_date']?.toString() ?? '';
              final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
              final qty =
                  double.tryParse(r['quantity']?.toString() ?? '0') ?? 0;
              final amount =
                  double.tryParse(r['amount']?.toString() ?? '0') ?? 0;
              final exchangeRate =
                  double.tryParse(r['exchange_rate']?.toString() ?? '1') ?? 1.0;
              final actualExRate = exchangeRate == 0 ? 1.0 : exchangeRate;
              final totalInCurrency = double.tryParse(
                      r['total_in_currency']?.toString() ??
                          amount.toString()) ??
                  amount;
              final currency = _getCurrencyName(r['currency']?.toString());

              final unitPriceForeign = qty > 0 ? totalInCurrency / qty : 0.0;

              return [
                dateStr,
                '\u200E${r['shipment_no']?.toString() ?? ''}',
                r['customer_name']?.toString() ?? '',
                r['item_name']?.toString() ?? '',
                _fmtNum(qty),
                '$currency ${_fmtNum(unitPriceForeign)}',
                _fmtNum(actualExRate),
                '$currency ${_fmtNum(totalInCurrency)}',
                _fmtNum(amount),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('عدد المعاملات: ${_rows.length}',
                  style: pw.TextStyle(
                      font: font, fontSize: 10, color: PdfColors.black)),
              pw.Text('إجمالي التكاليف: EGP ${_fmt(totalAmount)}',
                  style: pw.TextStyle(
                      font: fontBold, fontSize: 10, color: PdfColors.black)),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  Widget _buildHeader(String title) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 12,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF061B3A),
        border: Border(
            bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 25))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Tooltip(
                message: 'العودة إلى تقارير التكاليف',
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF061B3A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 30)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('رجوع',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ),
              if (_rows.isNotEmpty) ...[
                PopupMenuButton<bool>(
                  tooltip: 'تصدير كملف Excel',
                  onSelected: (isEnglish) {
                    if (!_exportLoading) _exportToExcel(isEnglish);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: false,
                      child: Text('تصدير بالعربية',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                    const PopupMenuItem(
                      value: true,
                      child: Text('Export in English',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF061B3A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 30)),
                    ),
                    child: _exportLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF10B981)))
                        : const Icon(Icons.table_chart_outlined,
                            color: Color(0xFF10B981), size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'طباعة / PDF',
                  child: GestureDetector(
                    onTap: _printReport,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF061B3A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 30)),
                      ),
                      child: const Icon(Icons.print_outlined,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDateField('من تاريخ', _fromCtrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateField('إلى تاريخ', _toCtrl),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  _fromCtrl.clear();
                  _toCtrl.clear();
                  _load();
                },
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: const Center(
                    child: Icon(Icons.clear, color: Colors.white54, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(String label, TextEditingController ctrl) {
    return GestureDetector(
      onTap: () => _pickDate(ctrl),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppTheme.primary, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ctrl.text.isEmpty ? label : ctrl.text,
                style: TextStyle(
                  color: ctrl.text.isEmpty ? Colors.white54 : Colors.white,
                  fontSize: 13,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    if (_rows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text('لا توجد معاملات',
                style: TextStyle(
                    color: Colors.white, fontFamily: 'Cairo', fontSize: 16)),
          ],
        ),
      );
    }

    final totalAmount = _rows.fold<double>(
        0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: const Color(0xFF072548),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 30)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      const Color(0xFF0EA5E9).withValues(alpha: 10),
                    ),
                    dataRowColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.hovered))
                        return const Color(0xFF0EA5E9).withValues(alpha: 6);
                      return Colors.transparent;
                    }),
                    columnSpacing: 32,
                    dataRowMinHeight: 42,
                    dataRowMaxHeight: 50,
                    columns: const [
                      DataColumn(
                          label: Text('التاريخ',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                      DataColumn(
                          label: Text('رقم الشحنة',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                      DataColumn(
                          label: Text('العميل',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                      DataColumn(
                          label: Text('البيان',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                      DataColumn(
                          label: Text('الكمية',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          numeric: true),
                      DataColumn(
                          label: Text('سعر الوحدة',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          numeric: true),
                      DataColumn(
                          label: Text('سعر الصرف',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          numeric: true),
                      DataColumn(
                          label: Text('الإجمالي بالعملة',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          numeric: true),
                      DataColumn(
                          label: Text('الإجمالي بالمصري',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          numeric: true),
                    ],
                    rows: _rows.map((r) {
                      final date = r['shipment_date']?.toString() ?? '';
                      final dateStr =
                          date.length >= 10 ? date.substring(0, 10) : date;
                      final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
                      final totalInCurrency =
                          (r['total_in_currency'] as num?)?.toDouble() ??
                              (r['amount'] as num?)?.toDouble() ?? 0;
                      final unitPriceForeign =
                          qty > 0 ? totalInCurrency / qty : 0.0;
                      final currCode = r['currency']?.toString();
                      final currName = _getCurrencyName(currCode);
                      return DataRow(cells: [
                        DataCell(Text(dateStr,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.white))),
                        DataCell(Text(
                            r['shipment_no'] != null &&
                                    r['shipment_no'].toString().isNotEmpty
                                ? '\u202A${r['shipment_no']}\u202C'
                                : '',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary))),
                        DataCell(Text(r['customer_name']?.toString() ?? '',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.white))),
                        DataCell(Text(r['item_name']?.toString() ?? '',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.white))),
                        DataCell(Text(_fmtNum(qty),
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.white))),
                        DataCell(Text(
                            '$currName ${_fmtNum(unitPriceForeign)}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.white))),
                        DataCell(Text(
                            _fmtNum(r['exchange_rate'] ?? 1.0),
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.white))),
                        DataCell(Text(
                            '$currName ${_fmtNum(totalInCurrency)}',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Colors.white))),
                        DataCell(Text(_fmtNum(r['amount']),
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary))),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('عدد المعاملات: ',
                  style: TextStyle(
                      color: Colors.white, fontSize: 13, fontFamily: 'Cairo')),
              Text('${_rows.length}',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
              const SizedBox(width: 24),
              const Text('إجمالي التكاليف: ',
                  style: TextStyle(
                      color: Colors.white, fontSize: 13, fontFamily: 'Cairo')),
              Text('EGP ${_fmt(totalAmount)}',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '0';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return n.toStringAsFixed(2);
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  String _getCurrencyName(String? code) {
    if (code == null) return 'EGP';
    switch (code.toUpperCase()) {
      case 'USD':
        return 'USD';
      case 'EUR':
        return 'EURO';
      case 'GBP':
        return 'GBP';
      case 'EGP':
        return 'EGP';
      default:
        return code;
    }
  }
}
