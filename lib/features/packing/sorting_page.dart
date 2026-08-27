import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/packing_order_sorting_dao.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/models/packing_order_sorting_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SortingPage extends StatefulWidget {
  const SortingPage({super.key});

  @override
  State<SortingPage> createState() => _SortingPageState();
}

class _SortingPageState extends State<SortingPage> {
  final _dao = PackingOrderSortingDao();
  final _treasuryDao = TreasuryDao();
  static const _currencyCode = 'EGP';
  List<PackingOrderSortingModel> _allSortings = [];
  List<PackingOrderSortingModel> _filtered = [];
  bool _loading = true;
  String _filter = 'pending';
  String _searchQuery = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _allSortings = await _dao.getAll();
    } catch (_) {}
    _applyFilter();
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    var list = List<PackingOrderSortingModel>.from(_allSortings);

    if (_filter != 'all') {
      list = list.where((s) => s.status == _filter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) =>
        s.productName.toLowerCase().contains(q)
      ).toList();
    }

    if (_dateFrom != null) {
      list = list.where((s) =>
        s.createdAt != null && !s.createdAt!.isBefore(_dateFrom!)
      ).toList();
    }

    if (_dateTo != null) {
      final endOfDay = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
      list = list.where((s) =>
        s.createdAt != null && !s.createdAt!.isAfter(endOfDay)
      ).toList();
    }

    _filtered = list;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_dateFrom ?? now) : (_dateTo ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
        _applyFilter();
      });
    }
  }

  Future<void> _sellSorting(PackingOrderSortingModel sorting) async {
    final treasuries = await _treasuryDao.getAll();
    if (treasuries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد خزن متاحة. يرجى إنشاء خزينة أولاً.',
                textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String? selectedTreasuryId;
    String? selectedTreasuryName;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final qty = double.tryParse(qtyCtrl.text) ?? 0;
          final price = double.tryParse(priceCtrl.text) ?? 0;
          final total = qty * price;
          final costTotal = qty * sorting.costPerKg;
          final profit = total - costTotal;
          final screenWidth = MediaQuery.of(ctx).size.width;
          final dialogWidth = (screenWidth - 48).clamp(280.0, 400.0);

          return AlertDialog(
            backgroundColor: const Color(0xFF1A2940),
            title: const Text('بيع فرز',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow('المنتج', sorting.productName,
                          valueColor: AppTheme.textPrimary),
                      const SizedBox(height: 4),
                      _infoRow(
                          'المتبقي',
                          '${sorting.remainingWeightKg.toStringAsFixed(0)} كجم',
                          valueColor: AppTheme.textPrimary),
                      const SizedBox(height: 14),
                      TextField(
                        controller: qtyCtrl,
                        decoration: InputDecoration(
                          labelText: 'الكمية المباعة (كجم)',
                          suffixText: 'كجم',
                          labelStyle: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: const Color(0x1AFFFFFF),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceCtrl,
                        decoration: InputDecoration(
                          labelText: 'سعر البيع (${AppUtils.currencySymbol(_currencyCode)}/كجم)',
                          suffixText: AppUtils.currencySymbol(_currencyCode),
                          labelStyle: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: const Color(0x1AFFFFFF),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0x1AFFFFFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1A2940),
                            value: selectedTreasuryId,
                            hint: const Text('اختر الخزنة المستهدفة',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 15,
                                    fontFamily: 'Cairo')),
                            items: treasuries
                                .map((t) => DropdownMenuItem<String>(
                                      value: t.id,
                                      child: Text(t.displayName,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'Cairo')),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                selectedTreasuryId = val;
                                selectedTreasuryName = treasuries.firstWhere((t) => t.id == val).displayName;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (qty > 0 && price > 0) ...[
                        const Divider(color: AppTheme.glassBorder),
                        const SizedBox(height: 6),
                        _infoRow('كمية البيع',
                            '${qty.toStringAsFixed(0)} كجم',
                            valueColor: AppTheme.textPrimary),
                        const SizedBox(height: 4),
                        _infoRow('اجمالي البيع',
                            '${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(_currencyCode)}',
                            valueColor: AppTheme.success),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: (qty > 0 &&
                        price > 0 &&
                        selectedTreasuryId != null &&
                        qty <= sorting.remainingWeightKg)
                    ? () => Navigator.pop(
                        ctx, {'quantity': qty, 'price': price, 'treasury_id': selectedTreasuryId, 'treasury_name': selectedTreasuryName})
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                ),
                child: const Text('تأكيد البيع',
                    style: TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final qty = result['quantity'] as double;
      final price = result['price'] as double;
      final treasuryId = result['treasury_id'] as String;
      final treasuryName = result['treasury_name'] as String;
      final amount = qty * price;

      try {
        await Supabase.instance.client.rpc('rpc_sell_sorting', params: {
          'p_sorting_id': sorting.id,
          'p_qty': qty,
          'p_price': price,
          'p_treasury_id': int.tryParse(treasuryId),
          'p_treasury_name': treasuryName,
        });

        await _load();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'تم البيع بنجاح - المبلغ: ${amount.toStringAsFixed(2)} ${AppUtils.currencySymbol(_currencyCode)}',
                  textDirection: TextDirection.rtl),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('خطأ: $e', textDirection: TextDirection.rtl),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  Map<String, Map<String, dynamic>> _buildSummary(List<PackingOrderSortingModel> items) {
    final summary = <String, Map<String, dynamic>>{};
    for (final s in items) {
      final sold = s.weightKg - s.remainingWeightKg;
      if (sold <= 0) continue;
      if (!summary.containsKey(s.productName)) {
        summary[s.productName] = {
          'totalWeight': 0.0,
          'soldWeight': 0.0,
          'totalSale': 0.0,
          'count': 0,
        };
      }
      final entry = summary[s.productName]!;
      entry['totalWeight'] = (entry['totalWeight'] as double) + s.weightKg;
      entry['soldWeight'] = (entry['soldWeight'] as double) + sold;
      entry['totalSale'] = (entry['totalSale'] as double) + s.totalSaleAmount;
      entry['count'] = (entry['count'] as int) + 1;
    }
    return summary;
  }

  String get _dateLabel {
    final from = _dateFrom != null ? DateFormat('yyyy-MM-dd').format(_dateFrom!) : '—';
    final to = _dateTo != null ? DateFormat('yyyy-MM-dd').format(_dateTo!) : '—';
    return 'من $from إلى $to';
  }

  Future<void> _exportExcel() async {
    final items = _filtered;
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
        );
      }
      return;
    }

    final excel = Excel.createExcel();
    final sheet = excel['تقارير الفرز'];

    final headerStyle = CellStyle(
      fontSize: 11,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1A5276'),
      horizontalAlign: HorizontalAlign.Center,
    );

    final headers = ['التاريخ', 'المنتج', 'رقم اللوت', 'الوزن الأصلي', 'المتبقي', 'الوزن المباع', 'اجمالي المبيعات', 'الخزنة', 'الحالة'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var i = 0; i < items.length; i++) {
      final s = items[i];
      final sold = s.weightKg - s.remainingWeightKg;
      final row = i + 1;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          TextCellValue(s.createdAt != null ? DateFormat('yyyy-MM-dd').format(s.createdAt!) : '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
          TextCellValue(s.productName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
          TextCellValue(s.lotNumber ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value =
          DoubleCellValue(s.weightKg);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value =
          DoubleCellValue(s.remainingWeightKg);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value =
          DoubleCellValue(sold);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value =
          DoubleCellValue(s.totalSaleAmount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value =
          TextCellValue(s.treasuryNames ?? '—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value =
          TextCellValue(s.isSoldOut ? 'تم البيع بالكامل' : (sold > 0 ? 'مباع جزئياً' : 'متاح'));
    }

    final summary = _buildSummary(items);
    if (summary.isNotEmpty) {
      final startRow = items.length + 3;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
          TextCellValue('ملخص المبيعات');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).cellStyle =
          CellStyle(bold: true, fontSize: 12);

      final sumHeaders = ['المنتج', 'العدد', 'الوزن المباع (كجم)', 'اجمالي المبيعات (${AppUtils.currencySymbol(_currencyCode)})'];
      for (var i = 0; i < sumHeaders.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: startRow + 1));
        cell.value = TextCellValue(sumHeaders[i]);
        cell.cellStyle = headerStyle;
      }

      var r = startRow + 2;
      for (final entry in summary.entries) {
        final v = entry.value;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
            TextCellValue(entry.key);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value =
            IntCellValue(v['count'] as int);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value =
            DoubleCellValue(v['soldWeight'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value =
            DoubleCellValue(v['totalSale'] as double);
        r++;
      }
    }

    final bytes = excel.save();
    if (bytes == null) return;

    final dir = await FileHelper.getExportDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${dir.path}/sorting_report_$dateStr.xlsx');
    await file.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التصدير: ${file.path}', textDirection: TextDirection.rtl), backgroundColor: AppTheme.success),
      );
    }
  }

  Future<void> _exportPdf() async {
    final items = _filtered;
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
        );
      }
      return;
    }

    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();
    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    pdf.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(bgImage, fit: pw.BoxFit.cover),
        ),
      ),
      build: (ctx) {
        final widgets = <pw.Widget>[
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Header(
              level: 0,
              child: pw.Text('تقرير الفرز',
                  style: pw.TextStyle(font: arabicBold, fontSize: 20)),
            ),
          ),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text('التاريخ: $_dateLabel',
                style: pw.TextStyle(font: arabicFont, fontSize: 12, color: PdfColors.grey700)),
          ),
          pw.SizedBox(height: 4),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text('عدد العناصر: ${items.length}',
                style: pw.TextStyle(font: arabicFont, fontSize: 11)),
          ),
          pw.SizedBox(height: 12),
        ];

        final summary = _buildSummary(items);
        if (summary.isNotEmpty) {
          widgets.add(pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Header(
              level: 1,
              child: pw.Text('ملخص المبيعات',
                  style: pw.TextStyle(font: arabicBold, fontSize: 14)),
            ),
          ));

          widgets.add(pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: arabicBold, fontSize: 10, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#1A5276')),
            headerAlignment: pw.Alignment.center,
            cellStyle: pw.TextStyle(font: arabicFont, fontSize: 9),
            cellAlignment: pw.Alignment.center,
            cellHeight: 24,
            headerHeight: 28,
            headers: ['المنتج', 'العدد', 'الوزن المباع (كجم)', 'اجمالي المبيعات (${AppUtils.currencySymbol(_currencyCode)})'],
            data: summary.entries.map((e) {
              final v = e.value;
              return [
                e.key,
                '${v['count']}',
                (v['soldWeight'] as double).toStringAsFixed(1),
                '${(v['totalSale'] as double).toStringAsFixed(2)} ${AppUtils.currencySymbol(_currencyCode)}',
              ];
            }).toList(),
          ));

          widgets.add(pw.SizedBox(height: 16));
        }

        widgets.add(pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Header(
            level: 1,
            child: pw.Text('التفاصيل',
                style: pw.TextStyle(font: arabicBold, fontSize: 14)),
          ),
        ));

        widgets.add(pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(font: arabicBold, fontSize: 8, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#1A5276')),
          headerAlignment: pw.Alignment.center,
          cellStyle: pw.TextStyle(font: arabicFont, fontSize: 7),
          cellAlignment: pw.Alignment.center,
          cellHeight: 18,
          headerHeight: 22,
          headers: ['التاريخ', 'المنتج', 'اللوت', 'الأصلي', 'المتبقي', 'المباع', 'المبيعات', 'الحالة'],
          data: items.map((s) {
            final sold = s.weightKg - s.remainingWeightKg;
            return [
              s.createdAt != null ? DateFormat('yyyy-MM-dd').format(s.createdAt!) : '',
              s.productName,
              s.lotNumber ?? '',
              s.weightKg.toStringAsFixed(1),
              s.remainingWeightKg.toStringAsFixed(1),
              sold.toStringAsFixed(1),
              s.totalSaleAmount.toStringAsFixed(2),
              s.isSoldOut ? 'تم البيع' : (sold > 0 ? 'جزئي' : 'متاح'),
            ];
          }).toList(),
        ));

        return widgets;
      },
    ));

    final bytes = await pdf.save();
    final dir = await FileHelper.getExportDirectory();
    final file = File('${dir.path}/sorting_report_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf');
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الحفظ في: ${file.path}', textDirection: TextDirection.rtl), backgroundColor: AppTheme.success),
      );
    }
  }

  Widget _buildSortingCard(PackingOrderSortingModel sorting, double width) {
    final dateStr = sorting.createdAt != null
        ? DateFormat('yyyy-MM-dd').format(sorting.createdAt!)
        : '—';
    final isSoldOut = sorting.isSoldOut;
    final totalQty = sorting.weightKg;
    final remainingQty = sorting.remainingWeightKg;
    final soldQty = totalQty - remainingQty;
    final costPerUnit = sorting.costPerKg;
    final totalValue = totalQty * costPerUnit;
    final isSmall = width < 400;
    final isMedium = width >= 400 && width < 700;
    final titleSize = isSmall ? 18.0 : (isMedium ? 20.0 : 22.0);
    final bodySize = isSmall ? 14.0 : (isMedium ? 16.0 : 18.0);
    final secondarySize = isSmall ? 12.0 : (isMedium ? 14.0 : 15.0);
    final statIconSize = isSmall ? 18.0 : 20.0;

    return Container(
      margin: const EdgeInsets.all(4),
      padding: EdgeInsets.all(isSmall ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D253E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSoldOut
              ? AppTheme.success.withValues(alpha: 0.3)
              : AppTheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF163A5F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: AppTheme.primary,
                  size: statIconSize,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sorting.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF163A5F),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  sorting.lotNumber ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: secondarySize,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              if (sorting.totalSaleAmount > 0) ...[
                const SizedBox(width: 8),
                _buildJournalButton(sorting, statIconSize),
              ],
            ],
          ),
          SizedBox(height: isSmall ? 8 : 12),
          Container(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isSoldOut
                    ? AppTheme.success.withValues(alpha: 0.15)
                    : AppTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSoldOut
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : AppTheme.warning,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isSoldOut ? AppTheme.success : AppTheme.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isSoldOut ? 'تم البيع بالكامل' : 'متاح',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSoldOut ? AppTheme.success : AppTheme.warning,
                      fontSize: secondarySize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: isSmall ? 8 : 12),
          _buildStatBox(
            icon: Icons.inventory_2_outlined,
            label: 'الكمية (${totalQty.toStringAsFixed(0)} كجم)',
            value: soldQty > 0 ? 'مباع ${soldQty.toStringAsFixed(0)}' : '—',
            valueColor: soldQty > 0 ? AppTheme.success : null,
            iconSize: statIconSize,
            fontSize: bodySize,
          ),
          SizedBox(height: isSmall ? 6 : 8),
          _buildStatBox(
            icon: Icons.scale_outlined,
            label: 'المتبقي',
            value: '${remainingQty.toStringAsFixed(0)} كجم',
            iconSize: statIconSize,
            fontSize: bodySize,
          ),
          if (sorting.totalSaleAmount > 0) ...[
            SizedBox(height: isSmall ? 6 : 8),
            _buildStatBox(
              icon: Icons.monetization_on_outlined,
              label: 'المبيعات',
              value: '${sorting.totalSaleAmount.toStringAsFixed(2)} ${AppUtils.currencySymbol(_currencyCode)}',
              valueColor: AppTheme.success,
              iconSize: statIconSize,
              fontSize: bodySize,
            ),
          ],
          SizedBox(height: isSmall ? 6 : 8),
          Text(
            dateStr,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: secondarySize,
              fontFamily: 'Cairo',
            ),
          ),
          if (!isSoldOut) ...[
            SizedBox(height: isSmall ? 8 : 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _sellSorting(sorting),
                icon: Icon(Icons.sell, size: isSmall ? 12 : 14),
                label: Text('بيع',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: isSmall ? 12 : 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isSmall ? 6 : 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildJournalButton(PackingOrderSortingModel sorting, double iconSize) {
    return GestureDetector(
      onTap: () async {
        final desc = 'بيع فرز - ${sorting.productName}';
        final client = Supabase.instance.client;
        try {
          final res = await client
              .from('v_journal_entry_lines')
              .select('entry_number, description')
              .ilike('description', '$desc%');

          if (res.isEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('لا يوجد قيد محاسبي مرتبط', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
              );
            }
            return;
          }

          final uniqueEntries = <String, String>{};
          for (final r in res) {
            final entryNo = r['entry_number']?.toString();
            final d = r['description']?.toString();
            if (entryNo != null && d != null) {
              uniqueEntries[entryNo] = d;
            }
          }

          if (uniqueEntries.length == 1) {
            if (context.mounted) {
              JournalEntryNavigationService.openForTransaction(context, entryNumber: uniqueEntries.keys.first);
            }
          } else {
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A2940),
                  title: const Text('القيود المحاسبية للمبيعات', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16)),
                  content: SizedBox(
                    width: 400,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: uniqueEntries.length,
                      itemBuilder: (context, index) {
                        final entryNo = uniqueEntries.keys.elementAt(index);
                        final descText = uniqueEntries.values.elementAt(index);
                        return ListTile(
                          title: Text(descText, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                          subtitle: Text('رقم القيد: $entryNo', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 11)),
                          trailing: const Icon(Icons.arrow_forward_ios, color: AppTheme.success, size: 14),
                          onTap: () {
                            Navigator.pop(ctx);
                            JournalEntryNavigationService.openForTransaction(context, entryNumber: entryNo);
                          },
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
                    ),
                  ],
                ),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            JournalEntryNavigationService.openForTransaction(
              context,
              description: desc,
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.success.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.success.withAlpha(40)),
        ),
        child: Icon(Icons.book_outlined, size: iconSize, color: AppTheme.success),
      ),
    );
  }

  Widget _buildStatBox({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    double iconSize = 16,
    double fontSize = 13,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF163A5F),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: iconSize),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: fontSize,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? AppTheme.textPrimary,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontFamily: 'Cairo')),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: valueColor ?? AppTheme.textPrimary,
                  fontSize: 14,
                  fontFamily: 'Cairo')),
        ),
      ],
    );
  }

  String _formatDateShort(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: AppTheme.backgroundGradient,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenW = constraints.maxWidth;
              final isSmall = screenW < 400;
              final isMedium = screenW >= 400 && screenW < 700;
              final titleFontSize = isSmall ? 16.0 : (isMedium ? 18.0 : 22.0);
              final chipFontSize = isSmall ? 10.0 : 12.0;
              final crossAxisCount = screenW >= 1200 ? 4 : (screenW >= 800 ? 3 : (screenW >= 500 ? 2 : 1));
              final cardPadding = isSmall ? 12.0 : 16.0;

              return Column(
                children: [
                  ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 12,
                            bottom: 12,
                            left: 8,
                            right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0x3805192D),
                          border: Border(
                              bottom: BorderSide(
                                  color:
                                      AppTheme.glassBorder.withAlpha(50))),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward,
                                      color: Colors.white),
                                  onPressed: () => context.pop(),
                                ),
                                Expanded(
                                  child: Text('الفرز',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo')),
                                ),
                                IconButton(
                                  icon: Icon(Icons.picture_as_pdf,
                                      color: AppTheme.danger,
                                      size: isSmall ? 18 : 20),
                                  onPressed: _exportPdf,
                                  tooltip: 'تصدير PDF',
                                ),
                                IconButton(
                                  icon: Icon(Icons.table_chart,
                                      color: AppTheme.success,
                                      size: isSmall ? 18 : 20),
                                  onPressed: _exportExcel,
                                  tooltip: 'تصدير Excel',
                                ),
                                IconButton(
                                  icon: Icon(Icons.refresh,
                                      color: AppTheme.primary,
                                      size: isSmall ? 18 : 20),
                                  onPressed: _load,
                                ),
                              ],
                            ),
                            SizedBox(height: isSmall ? 4 : 8),
                            TextField(
                              decoration: InputDecoration(
                                hintText: 'بحث...',
                                hintStyle: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontFamily: 'Cairo',
                                    fontSize: chipFontSize),
                                prefixIcon: Icon(Icons.search,
                                    color: AppTheme.textSecondary,
                                    size: isSmall ? 16 : 18),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _searchQuery = '';
                                            _applyFilter();
                                          });
                                        },
                                        child: Icon(Icons.close,
                                            color: AppTheme.textSecondary,
                                            size: isSmall ? 14 : 16),
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.05),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 10, vertical: isSmall ? 6 : 8),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                              ),
                              style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Cairo',
                                  fontSize: chipFontSize),
                              onChanged: (v) {
                                setState(() {
                                  _searchQuery = v;
                                  _applyFilter();
                                });
                              },
                            ),
                            SizedBox(height: isSmall ? 4 : 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _pickDate(isFrom: true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _dateFrom != null
                                            ? AppTheme.primary.withValues(alpha: 0.15)
                                            : Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: _dateFrom != null
                                                ? AppTheme.primary
                                                : AppTheme.glassBorder),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.date_range,
                                              size: isSmall ? 12 : 14,
                                              color: AppTheme.textSecondary),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              _dateFrom != null
                                                  ? _formatDateShort(_dateFrom!)
                                                  : 'من تاريخ',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: _dateFrom != null
                                                      ? AppTheme.primary
                                                      : AppTheme.textSecondary,
                                                  fontSize: isSmall ? 10 : 11,
                                                  fontFamily: 'Cairo'),
                                            ),
                                          ),
                                          if (_dateFrom != null)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _dateFrom = null;
                                                  _applyFilter();
                                                });
                                              },
                                              child: Icon(Icons.close,
                                                  size: isSmall ? 10 : 12,
                                                  color: AppTheme.textSecondary),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _pickDate(isFrom: false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _dateTo != null
                                            ? AppTheme.primary.withValues(alpha: 0.15)
                                            : Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: _dateTo != null
                                                ? AppTheme.primary
                                                : AppTheme.glassBorder),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.date_range,
                                              size: isSmall ? 12 : 14,
                                              color: AppTheme.textSecondary),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              _dateTo != null
                                                  ? _formatDateShort(_dateTo!)
                                                  : 'إلى تاريخ',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: _dateTo != null
                                                      ? AppTheme.primary
                                                      : AppTheme.textSecondary,
                                                  fontSize: isSmall ? 10 : 11,
                                                  fontFamily: 'Cairo'),
                                            ),
                                          ),
                                          if (_dateTo != null)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _dateTo = null;
                                                  _applyFilter();
                                                });
                                              },
                                              child: Icon(Icons.close,
                                                  size: isSmall ? 10 : 12,
                                                  color: AppTheme.textSecondary),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isSmall ? 4 : 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildFilterChip('قيد الانتظار', 'pending', chipFontSize),
                                  SizedBox(width: isSmall ? 4 : 8),
                                  _buildFilterChip('تم البيع', 'sold', chipFontSize),
                                  SizedBox(width: isSmall ? 4 : 8),
                                  _buildFilterChip('الكل', 'all', chipFontSize),
                                  const SizedBox(width: 8),
                                  Text('${_filtered.length} عنصر',
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: chipFontSize,
                                          fontFamily: 'Cairo')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary))
                        : _filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sort,
                                        size: 64,
                                        color: AppTheme.textSecondary
                                            .withValues(alpha: 0.3)),
                                    const SizedBox(height: 16),
                                    Text(
                                      _filter == 'pending'
                                          ? 'لا توجد عناصر فرز قيد الانتظار'
                                          : _filter == 'sold'
                                              ? 'لا توجد عناصر فرز تم بيعها'
                                              : 'لا توجد عناصر فرز',
                                      style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 16,
                                          fontFamily: 'Cairo'),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                color: AppTheme.primary,
                                child: crossAxisCount == 1
                                    ? ListView.builder(
                                        padding: EdgeInsets.all(cardPadding),
                                        itemCount: _filtered.length,
                                        itemBuilder: (context, index) {
                                          return _buildSortingCard(
                                              _filtered[index], screenW - cardPadding * 2);
                                        },
                                      )
                                    : GridView.builder(
                                        padding: EdgeInsets.all(cardPadding),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisExtent: 310.0,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                        ),
                                        itemCount: _filtered.length,
                                        itemBuilder: (context, index) {
                                          final cardW = (screenW - cardPadding * 2 - 12 * (crossAxisCount - 1)) / crossAxisCount;
                                          return _buildSortingCard(
                                              _filtered[index], cardW);
                                        },
                                      ),
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, double fontSize) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = value;
          _applyFilter();
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : AppTheme.glassBorder),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: selected
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
      ),
    );
  }
}
