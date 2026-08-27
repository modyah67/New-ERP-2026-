import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xls;
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/station_model.dart';
import '../../data/models/warehouse_movement_model.dart';
import 'warehouse_tracking_cubit.dart';
import 'warehouse_tracking_state.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class WarehouseTrackingDetailsPage extends StatefulWidget {
  final StationModel station;
  final WarehouseTrackingCubit cubit;

  const WarehouseTrackingDetailsPage({
    super.key,
    required this.station,
    required this.cubit,
  });

  @override
  State<WarehouseTrackingDetailsPage> createState() =>
      _WarehouseTrackingDetailsPageState();
}

class _WarehouseTrackingDetailsPageState
    extends State<WarehouseTrackingDetailsPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  MovementType? _selectedType;
  late final WarehouseTrackingCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = widget.cubit;
    _cubit.loadStationDetail(widget.station);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isMobile),
            const SizedBox(height: 16),
            _buildFilters(isMobile),
            const SizedBox(height: 16),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.warehouse_outlined,
              color: AppTheme.accent, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.station.name,
                    style: TextStyle(
                        fontSize: isMobile ? 20 : 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
                Text('تتبع حركات المخزن',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 13)),
              ],
            ),
          ),
        ),
        // PDF Button
        // _buildActionBtn(
        //   Icons.picture_as_pdf,
        //   'PDF',
        //   Colors.red,
        //   () => _generatePdf(),
        // ),
        // const SizedBox(width: 8),
        // // Save PDF Button
        // _buildActionBtn(
        //   Icons.save_alt,
        //   'حفظ PDF',
        //   AppTheme.warning,
        //   () => _savePdf(),
        // ),
        // const SizedBox(width: 8),
        // // Excel Button
        // _buildActionBtn(
        //   Icons.table_chart,
        //   'Excel',
        //   AppTheme.success,
        //   () => _exportExcel(),
        // ),
      ],
    );
  }

  Widget _buildActionBtn(
      IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _buildFilters(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 0.3)),
      ),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildDateField('من', _fromDate, (d) {
                      setState(() => _fromDate = d);
                      _applyFilters();
                    })),
                    const SizedBox(width: 8),
                    Expanded(child: _buildDateField('إلى', _toDate, (d) {
                      setState(() => _toDate = d);
                      _applyFilters();
                    })),
                  ],
                ),
                const SizedBox(height: 8),
                _buildTypeFilter(),
                if (_fromDate != null || _toDate != null || _selectedType != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('مسح الفلاتر',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                      onPressed: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                          _selectedType = null;
                        });
                        _applyFilters();
                      },
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildDateField('من', _fromDate, (d) {
                    setState(() => _fromDate = d);
                    _applyFilters();
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _buildDateField('إلى', _toDate, (d) {
                    setState(() => _toDate = d);
                    _applyFilters();
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildTypeFilter()),
                const SizedBox(width: 12),
                if (_fromDate != null || _toDate != null || _selectedType != null)
                  TextButton.icon(
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('مسح الفلاتر',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    onPressed: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _selectedType = null;
                      });
                      _applyFilters();
                    },
                  ),
              ],
            ),
    );
  }

  Widget _buildDateField(
      String label, DateTime? date, Function(DateTime) onPicked) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontFamily: 'Cairo', fontSize: 12, color: AppTheme.textSecondary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.glassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.glassBorder),
          ),
          suffixIcon: date != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  onPressed: () {
                    onPicked(DateTime(2000));
                  },
                )
              : const Icon(Icons.calendar_today, size: 14),
        ),
        child: Text(
          date != null ? AppUtils.formatDate(date) : 'اختر التاريخ',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    return DropdownButtonFormField<MovementType>(
      initialValue: _selectedType,
      decoration: InputDecoration(
        labelText: 'نوع الحركة',
        labelStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: 12, color: AppTheme.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.glassBorder),
        ),
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text('الكل', style: TextStyle(fontFamily: 'Cairo'))),
        DropdownMenuItem(
            value: MovementType.purchase,
            child: Text('مشتريات', style: TextStyle(fontFamily: 'Cairo'))),
        DropdownMenuItem(
            value: MovementType.lotReceipt,
            child: Text('شراء محصول', style: TextStyle(fontFamily: 'Cairo'))),
        DropdownMenuItem(
            value: MovementType.packing,
            child: Text('تعبئة', style: TextStyle(fontFamily: 'Cairo'))),
        DropdownMenuItem(
            value: MovementType.materialTransfer,
            child: Text('مواد تعبئة', style: TextStyle(fontFamily: 'Cairo'))),
        DropdownMenuItem(
            value: MovementType.transferIn,
            child: Text('تحويل وارد', style: TextStyle(fontFamily: 'Cairo'))),
        DropdownMenuItem(
            value: MovementType.transferOut,
            child: Text('تحويل صادر', style: TextStyle(fontFamily: 'Cairo'))),
        DropdownMenuItem(
            value: MovementType.lotReturn,
            child: Text('مرتجع محصول', style: TextStyle(fontFamily: 'Cairo'))),
      ],
      onChanged: (val) {
        setState(() => _selectedType = val);
        _applyFilters();
      },
    );
  }

  void _applyFilters() {
    _cubit.filterByDate(widget.station, _fromDate, _toDate);
  }

  Widget _buildContent() {
    return Column(
      children: [
        Expanded(
          child: BlocBuilder<WarehouseTrackingCubit, WarehouseTrackingState>(
            builder: (context, state) {
              if (state is WarehouseTrackingDetailLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is WarehouseTrackingDetailLoaded) {
                var movements = state.movements;
                if (_selectedType != null) {
                  movements =
                      movements.where((m) => m.type == _selectedType).toList();
                }
                if (movements.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildMovementsList(movements);
              }
              if (state is WarehouseTrackingError) {
                return Center(child: Text(state.message,
                    style: const TextStyle(color: AppTheme.textSecondary)));
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMovementsList(List<WarehouseMovementModel> movements) {
    return ListView.builder(
      itemCount: movements.length,
      itemBuilder: (context, index) {
        return _buildMovementCard(movements[index], index);
      },
    );
  }

  Widget _buildMovementCard(WarehouseMovementModel movement, int index) {
    final (Color color, IconData icon) = _getTypeStyle(movement.type);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 20)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 15 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          movement.type.label,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        movement.referenceNumber,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (movement.productName != null)
                    Text(
                      movement.productName!,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (movement.details != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      movement.details!,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Date + quantity
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (movement.date != null)
                  Text(
                    AppUtils.formatDate(movement.date!),
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: AppTheme.textSecondary),
                  ),
                if (movement.quantity != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${AppUtils.formatNumber(movement.quantity!)} ${movement.unit ?? "كجم"}',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  (Color, IconData) _getTypeStyle(MovementType type) {
    switch (type) {
      case MovementType.purchase:
        return (AppTheme.primary, Icons.shopping_cart_outlined);
      case MovementType.lotReceipt:
        return (AppTheme.accent, Icons.eco_outlined);
      case MovementType.packing:
        return (AppTheme.warning, Icons.checklist_outlined);
      case MovementType.materialTransfer:
        return (AppTheme.success, Icons.inventory_2_outlined);
      case MovementType.transferIn:
        return (AppTheme.success, Icons.arrow_downward);
      case MovementType.transferOut:
        return (AppTheme.danger, Icons.arrow_upward);
      case MovementType.lotReturn:
        return (AppTheme.danger, Icons.assignment_return_outlined);
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined,
              size: 64,
              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text(
            'لا توجد حركات',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          const Text(
            'لم يتم تسجيل أي حركات في هذا المخزن',
            style: TextStyle(
                color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── PDF ──

  static pw.Font? _arabicFont;
  static pw.Font? _arabicBoldFont;

  static Future<void> _loadFonts() async {
    if (_arabicFont != null) return;
    final regular =
        await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _arabicFont = pw.Font.ttf(regular);
    _arabicBoldFont = pw.Font.ttf(bold);
  }

  Future<void> _generatePdf() async {
    await _loadFonts();
    final movements = _getCurrentMovements();
    final pdf = await _buildPdf(movements);
    await Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: 'حركات مخزن ${widget.station.name}',
    );
  }

  Future<void> _savePdf() async {
    await _loadFonts();
    final movements = _getCurrentMovements();
    final bytes = await _buildPdf(movements);
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'حركات مخزن ${widget.station.name}';
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الملف بنجاح', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  List<WarehouseMovementModel> _getCurrentMovements() {
    final state = _cubit.state;
    if (state is WarehouseTrackingDetailLoaded) {
      var movements = state.movements;
      if (_selectedType != null) {
        movements =
            movements.where((m) => m.type == _selectedType).toList();
      }
      return movements;
    }
    return [];
  }

  Future<Uint8List> _buildPdf(List<WarehouseMovementModel> movements) async {
    final doc = pw.Document();
    final theme =
        pw.ThemeData.withFont(base: _arabicFont!, bold: _arabicBoldFont!);

    final grouped = _groupMovementsByProduct(movements);

    final content = <pw.Widget>[];
    content.addAll([
      pw.Center(
        child: pw.Text('حركات مخزن ${widget.station.name}',
            style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 20)),
      ),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
            'كود: ${widget.station.code} | التاريخ: ${AppUtils.formatDate(DateTime.now())}',
            style: pw.TextStyle(
                font: _arabicFont!, fontSize: 12, color: PdfColors.grey600)),
      ),
      pw.SizedBox(height: 16),
    ]);

    if (_fromDate != null || _toDate != null) {
      content.add(pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF5F5F5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          'الفلتر: ${_fromDate != null ? "من ${AppUtils.formatDate(_fromDate!)}" : ""} ${_toDate != null ? "إلى ${AppUtils.formatDate(_toDate!)}" : ""}',
          style: pw.TextStyle(font: _arabicFont!, fontSize: 11),
        ),
      ));
      content.add(pw.SizedBox(height: 12));
    }

    for (final entry in grouped.entries) {
      final productName = entry.key;
      final items = entry.value;
      final totalQty =
          items.fold<double>(0, (s, m) => s + (m.quantity ?? 0));

      content.add(pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFF1A3A5C),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(productName,
                style: pw.TextStyle(
                    font: _arabicBoldFont!,
                    fontSize: 13,
                    color: PdfColors.white)),
            pw.Text(
                '${items.length} حركة - الكمية: ${AppUtils.formatNumber(totalQty)} كجم',
                style: pw.TextStyle(
                    font: _arabicFont!,
                    fontSize: 10,
                    color: PdfColors.grey300)),
          ],
        ),
      ));
      content.add(pw.SizedBox(height: 6));
      content.add(pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(
            font: _arabicBoldFont!, fontSize: 9, color: PdfColors.white),
        headerDecoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFF424242)),
        cellStyle: pw.TextStyle(font: _arabicFont!, fontSize: 8),
        cellAlignment: pw.Alignment.centerRight,
        cellHeight: 26,
        headers: ['التاريخ', 'النوع', 'الرقم', 'الكمية', 'المورد', 'التفاصيل'],
        data: items
            .map((m) => [
                  AppUtils.formatDate(m.date ?? DateTime(2000)),
                  m.type.label,
                  m.referenceNumber,
                  m.quantity != null
                      ? '${AppUtils.formatNumber(m.quantity!)} ${m.type == MovementType.materialTransfer ? "قطعة" : "كجم"}'
                      : '-',
                  m.supplierName ?? '-',
                  m.details ?? '-',
                ])
            .toList(),
      ));
      content.add(pw.SizedBox(height: 6));
      content.add(pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF5F5F5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('إجمالي $productName: ',
                style: pw.TextStyle(
                    font: _arabicBoldFont!,
                    fontSize: 9,
                    color: PdfColors.grey700)),
            pw.Text('${AppUtils.formatNumber(totalQty)} كجم',
                style: pw.TextStyle(
                    font: _arabicBoldFont!,
                    fontSize: 10,
                    color: PdfColor.fromInt(0xFF1A3A5C))),
          ],
        ),
      ));
      content.add(pw.SizedBox(height: 14));
    }

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 30),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(bgImage, fit: pw.BoxFit.cover),
        ),
      ),
      build: (pw.Context ctx) => content,
    ));

    return doc.save();
  }

  Map<String, List<WarehouseMovementModel>> _groupMovementsByProduct(
      List<WarehouseMovementModel> movements) {
    final grouped = <String, List<WarehouseMovementModel>>{};
    for (final m in movements) {
      final key = m.productName ?? 'غير محدد';
      grouped.putIfAbsent(key, () => []).add(m);
    }
    return grouped;
  }

  // ── Excel ──

  Future<void> _exportExcel() async {
    final movements = _getCurrentMovements();
    final excel = xls.Excel.createExcel();
    final sheet = excel['حركات المخزن'];

    final grouped = _groupMovementsByProduct(movements);

    // Header row
    sheet.appendRow([
      xls.TextCellValue('الصنف'),
      xls.TextCellValue('التاريخ'),
      xls.TextCellValue('النوع'),
      xls.TextCellValue('الرقم المرجعي'),
      xls.TextCellValue('الكمية'),
      xls.TextCellValue('المورد'),
      xls.TextCellValue('التفاصيل'),
    ]);

    for (final entry in grouped.entries) {
      final productName = entry.key;
      final items = entry.value;
      final totalQty = items.fold<double>(0, (s, m) => s + (m.quantity ?? 0));

      for (final m in items) {
        sheet.appendRow([
          xls.TextCellValue(productName),
          xls.TextCellValue(m.date != null ? AppUtils.formatDate(m.date!) : '-'),
          xls.TextCellValue(m.type.label),
          xls.TextCellValue(m.referenceNumber),
          xls.TextCellValue(
              m.quantity != null ? '${AppUtils.formatNumber(m.quantity!)} ${m.type == MovementType.materialTransfer ? "قطعة" : "كجم"}' : '-'),
          xls.TextCellValue(m.supplierName ?? '-'),
          xls.TextCellValue(m.details ?? '-'),
        ]);
      }

      // Category subtotal row
      sheet.appendRow([
        xls.TextCellValue(''),
        xls.TextCellValue(''),
        xls.TextCellValue(''),
        xls.TextCellValue('إجمالي $productName'),
        xls.TextCellValue('${AppUtils.formatNumber(totalQty)} كجم'),
        xls.TextCellValue(''),
        xls.TextCellValue(''),
      ]);

      // Empty separator row
      sheet.appendRow([xls.TextCellValue('')]);
    }

    for (int i = 0; i < 7; i++) {
      sheet.setColumnWidth(i, 20);
    }

    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final dir = await FileHelper.getExportDirectory();
    final fileName = 'حركات مخزن ${widget.station.name}';
    final path = '${dir.path}/$fileName.xlsx';
    final file = File(path);
    await file.writeAsBytes(fileBytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ ملف Excel بنجاح', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }
}
