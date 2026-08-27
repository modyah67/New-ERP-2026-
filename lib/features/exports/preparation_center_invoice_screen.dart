import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../core/utils.dart';
import '../../core/ui_utils.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/dao/shipment_recipe_snapshot_dao.dart';
import '../../data/dao/supplier_settlement_dao.dart';
import '../../data/dao/prep_center_cost_item_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/shipment_recipe_snapshot_model.dart';
import '../../data/models/supplier_settlement_model.dart';
import '../../data/models/prep_center_cost_item_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/item_model.dart';
import '../../data/dao/item_dao.dart';
import '../../data/services/prep_center_breakdown_adapter.dart';
import '../../data/services/prep_center_auto_populate_service.dart';
import '../../core/services/shipment_profitability_service.dart';
import 'prep_center_invoice_pdf_service.dart';

class PreparationCenterInvoiceScreen extends StatefulWidget {
  final int shipmentId;
  const PreparationCenterInvoiceScreen({super.key, required this.shipmentId});

  @override
  State<PreparationCenterInvoiceScreen> createState() => _PreparationCenterInvoiceScreenState();
}

class _PreparationCenterInvoiceScreenState extends State<PreparationCenterInvoiceScreen> {
  final _dao = ExportShipmentDao();
  final _itemDao = ExportShipmentItemDao();
  final _itemsDao = ItemDao();
  final _packingDao = PackingOrderDao();
  final _snapshotDao = ShipmentRecipeSnapshotDao();
  final _settlementDao = SupplierSettlementDao();
  final _costItemDao = PrepCenterCostItemDao();
  final _supplierDao = SupplierDao();
  final _autoPopulate = PrepCenterAutoPopulateService();
  final _breakdownAdapter = PrepCenterBreakdownAdapter();
  final _profitabilityService = ShipmentProfitabilityService();

  ExportShipmentModel? _shipment;
  List<Map<String, dynamic>> _shipmentItems = [];
  ShipmentProfitabilityResult? _profitResult;
  List<PackingOrderModel> _packingOrders = [];
  List<ShipmentRecipeSnapshotModel> _recipeSnapshots = [];
  List<SupplierSettlementModel> _settlements = [];
  List<PrepCenterCostItemModel> _costItems = [];
  List<SupplierModel> _suppliers = [];
  List<ItemModel> _productItems = [];
  PrepCenterBreakdownResult _breakdownResult = const PrepCenterBreakdownResult();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  String? _error;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _dao.getById(widget.shipmentId),
        _itemDao.getByShipmentId(widget.shipmentId),
        _packingDao.getByShipmentIdViaItems(widget.shipmentId),
        _settlementDao.getByShipment(widget.shipmentId.toString()),
        _costItemDao.getByShipment(widget.shipmentId.toString()),
        _supplierDao.getAll(),
        _itemsDao.getAll(limit: 2000),
        _breakdownAdapter.getForShipment(widget.shipmentId.toString()),
        _snapshotDao.getByShipment(widget.shipmentId),
        _profitabilityService.calculateShipment(widget.shipmentId.toString()),
      ]);

      final s = results[0] as ExportShipmentModel?;
      if (s == null) { setState(() { _error = '⚠️ الشحنة غير موجودة'; _loading = false; }); return; }

      final items = results[1] as List<Map<String, dynamic>>;
      final orders = results[2] as List<PackingOrderModel>;
      final settlements = results[3] as List<SupplierSettlementModel>;
      final costItems = results[4] as List<PrepCenterCostItemModel>;
      final suppliers = results[5] as List<SupplierModel>;
      final productItems = results[6] as List<ItemModel>;
      final breakdown = results[7] as PrepCenterBreakdownResult;
      final recipeSnapshots = results[8] as List<ShipmentRecipeSnapshotModel>;
      final profitResult = results[9] as ShipmentProfitabilityResult?;

      if (!mounted) return;
      setState(() {
        _shipment = s;
        _shipmentItems = items;
        _packingOrders = orders;
        _recipeSnapshots = recipeSnapshots;
        _settlements = settlements;
        _costItems = costItems;
        _suppliers = suppliers;
        _productItems = productItems;
        _breakdownResult = breakdown;
        _profitResult = profitResult;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '⚠️ خطأ في تحميل البيانات: $e'; _loading = false; });
    }
  }

  // ── Source selection ──

  /// Use shipment_cost_breakdown as primary source when it has data.
  bool get _useBreakdown => _breakdownResult.hasData;

  // ── Computed totals ──

  double get _totalSupplierAmount => _useBreakdown
      ? _breakdownResult.totalSupplierAmount
      : _settlements.fold(0.0, (s, r) => s + r.totalAmount);

  double get _totalPackingCost => _useBreakdown
      ? _breakdownResult.totalPackingCost
      : _costItems
          .where((c) => const {'PACKAGING', 'LABELS', 'STICKERS'}.contains(c.costType))
          .fold(0.0, (s, r) => s + r.totalCost);

  double get _totalLogisticsCost => _useBreakdown
      ? _breakdownResult.totalLogisticsCost
      : _costItems
          .where((c) => c.costType == 'TRANSPORT' || c.costType == 'DIESEL' || c.costType == 'COOLING')
          .fold(0.0, (s, r) => s + r.totalCost);

  double get _totalAdminCost => _useBreakdown
      ? _breakdownResult.totalAdminCost
      : _costItems.fold(0.0, (s, r) => s + r.totalCost) - _totalPackingCost - _totalLogisticsCost;

  double get _totalOtherCost => _totalLogisticsCost + _totalAdminCost;

  double get _totalCostItems => _totalPackingCost + _totalOtherCost;

  double get _totalRevenue {
    if (_shipment == null) return 0;
    return _shipment!.totalRevenueEgp;
  }

  double get _grandTotalCost => _useBreakdown
      ? _breakdownResult.grandTotalCost
      : _totalSupplierAmount + _totalCostItems;

  double get _netProfit => _profitResult?.netProfit ?? (_totalRevenue - _grandTotalCost);

  double get _profitMargin =>
      _profitResult?.netMargin ?? (_totalRevenue > 0 ? (_netProfit / _totalRevenue * 100) : 0);

  double get _roi =>
      _grandTotalCost > 0 ? (_netProfit / _grandTotalCost * 100) : 0;

  double get _recipeTotalCost =>
      _recipeSnapshots.fold(0.0, (s, r) => s + r.totalCost);

  int get _totalCartons =>
      _packingOrders.fold<int>(0, (s, o) => s + o.cartonCount);

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('فاتورة مركز التحضير — ${_shipment?.shipmentNo ?? ''}',
              style: const TextStyle(fontSize: 16)),
          actions: [
            if (_shipment != null)
              IconButton(
                icon: const Icon(Icons.auto_fix_high),
                tooltip: 'توليد تلقائي من وصفات التعبئة',
                onPressed: () => _autoGenerate(),
              ),
            if (_shipment != null)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'PDF',
                onPressed: () => _printPdf(),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsRow(),
            const SizedBox(height: 16),
            _buildHeaderCard(),
            const SizedBox(height: 16),
            if (_shipmentItems.isNotEmpty) ...[
              _buildSection('بيان المنتجات المصدرة', _buildProductSummaryTable(),
                  color: const Color(0xFF1565C0)),
              const SizedBox(height: 16),
            ],
            _buildSection('ملخص التعبئة', _buildPackingSummary()),
            const SizedBox(height: 16),
            _buildSection('بيان المصروفات (تسوية موردين + مصروفات)', _buildUnifiedExpensesTable(),
                color: const Color(0xFFE65100)),
            const SizedBox(height: 16),
            _buildFinancialSummary(),
            const SizedBox(height: 16),
            if (_recipeSnapshots.isNotEmpty && _totalCartons > 0)
              _buildRecipeConsumptionCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── Stats Row ──

  Widget _buildStatsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = _buildStatCards();
        if (constraints.maxWidth < 700) {
          return Wrap(spacing: 8, runSpacing: 8, children: cards);
        }
        return Row(children: cards.map((c) => Expanded(child: c)).toList());
      },
    );
  }

  List<Widget> _buildStatCards() {
    final s = _shipment;
    return [
      _statCard('الوزن الصافي', '${s?.netWeight.toStringAsFixed(1) ?? '—'} كجم', Colors.blue),
      _statCard('عدد الكراتين', '${s?.cartonsCount ?? '—'}', Colors.teal),
      _statCard('إجمالي التكلفة', '${AppUtils.formatNumber(_grandTotalCost)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}', Colors.orange),
      _statCard('إجمالي الإيراد', '${AppUtils.formatNumber(_totalRevenue)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}', Colors.green),
      _statCard('صافي الربح', '${AppUtils.formatNumber(_netProfit)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
          _netProfit >= 0 ? Colors.green : Colors.red),
      _statCard('هامش الربح', '${_profitMargin.toStringAsFixed(1)}%',
          _profitMargin >= 0 ? Colors.green : Colors.red),
    ];
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Section wrapper ──

  Widget _buildSection(String title, Widget child, {Color? color}) {
    final bgColor = color ?? const Color(0xFF1B5E20);
    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  // ── Header Card ──

  Widget _buildHeaderCard() {
    final s = _shipment!;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(children: [
                _infoChip('التاريخ', s.shipmentDate != null ? AppUtils.formatDate(s.shipmentDate!) : '—'),
                const SizedBox(width: 32),
                _infoChip('رقم الشحنة', s.shipmentNo),
                const SizedBox(width: 32),
                _infoChip('اسم العميل', s.customerName ?? '—'),
              ]),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.green[900]!.withAlpha(60), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  const Text('مركز التحضير',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('${AppUtils.formatNumber(_grandTotalCost)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                  Text('إجمالي التكاليف',
                      style: TextStyle(color: Colors.green[200], fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Directionality(textDirection: TextDirection.ltr, child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
      ],
    );
  }

  // ── Product Summary ──

  Widget _buildProductSummaryTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dataTable(
          ['المنتج', 'البيان', 'الكمية', 'الوزن'],
          _shipmentItems.map((item) => [
            item['product_name']?.toString() ?? '—',
            'عدد كرتون الخدمة الفعلي',
            '${item['quantity'] ?? 0}',
            '${_d(item['weight_per_carton'])} كجم',
          ]).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'إجمالي الكميات: ${_shipmentItems.fold<int>(0, (s, i) => s + (int.tryParse(i['quantity']?.toString() ?? '0') ?? 0))} | '
          'الوزن الصافي: ${_shipmentItems.fold<double>(0.0, (s, i) => s + (double.tryParse(i['weight_per_carton']?.toString() ?? '0') ?? 0)).toStringAsFixed(1)} كجم',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  // ── Packing Summary ──

  Widget _buildPackingSummary() {
    if (_packingOrders.isEmpty) {
      return const Text('لا توجد أوامر تعبئة لهذه الشحنة', style: TextStyle(color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dataTable(
          ['المنتج', 'الدرجة', 'عدد الكراتين', 'الوزن الصافي', 'الوزن الإجمالي'],
          _packingOrders.map((o) => [
            o.productName ?? '—',
            o.grade,
            '${o.cartonCount}',
            '${o.totalNetWeight.toStringAsFixed(1)} كجم',
            '${o.totalGrossWeight.toStringAsFixed(1)} كجم',
          ]).toList(),
        ),
        if (_totalPackingCost > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('(تكاليف التعبئة مدرجة ضمن جدول المصروفات أدناه)',
                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
          ),
        const SizedBox(height: 8),
        Text(
          'الإجمالي: $_totalCartons كرتونة | '
          '${_packingOrders.fold<double>(0.0, (s, o) => s + o.totalNetWeight).toStringAsFixed(1)} كجم صافي | '
          '${_packingOrders.fold<double>(0.0, (s, o) => s + o.totalGrossWeight).toStringAsFixed(1)} كجم إجمالي',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  // ── Unified Expenses Table (Excel-matching) ──

  Widget _buildUnifiedExpensesTable() {
    if (_useBreakdown) return _buildBreakdownExpensesTable();
    if (_settlements.isEmpty && _costItems.isEmpty) {
      return Column(
        children: [
          const Text('لا توجد مصروفات مسجلة', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _showAddSettlementDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('تسوية مورد'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _showAddCostItemDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('مصروف'),
            ),
          ]),
        ],
      );
    }

    final headers = ['البيان', 'النوع', 'الكمية', 'السعر', 'القيمة', 'المورد', 'ملاحظات'];

    final rows = <_ExpenseRow>[];

    for (var i = 0; i < _settlements.length; i++) {
      final s = _settlements[i];
      rows.add(_ExpenseRow(
        originalIndex: i,
        isSettlement: true,
        cells: [
          s.productName ?? '—',
          s.grade,
          '${s.weightKg.toStringAsFixed(1)} كجم',
          '${s.unitPrice.toStringAsFixed(2)}',
          '${s.totalAmount.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
          s.supplierName ?? '—',
          s.notes ?? '—',
        ],
      ));
    }

    for (var i = 0; i < _costItems.length; i++) {
      final c = _costItems[i];
      rows.add(_ExpenseRow(
        originalIndex: i,
        isSettlement: false,
        cells: [
          c.description.isNotEmpty ? c.description : c.costTypeLabel,
          c.costTypeLabel,
          c.qty.toStringAsFixed(1),
          '${c.unitPrice.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
          '${c.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
          '—',
          c.notes ?? '—',
        ],
      ));
    }

    // Sort: settlements first, then cost items
    rows.sort((a, b) => a.isSettlement == b.isSettlement ? 0 : (a.isSettlement ? -1 : 1));

    final totalSettlements = _settlements.fold<double>(0.0, (s, r) => s + r.totalAmount);
    final totalCosts = _costItems.fold<double>(0.0, (s, r) => s + r.totalCost);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('تسوية موردين: ${AppUtils.formatNumber(totalSettlements)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green[800])),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('مصروفات: ${AppUtils.formatNumber(totalCosts)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[800])),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('الإجمالي: ${AppUtils.formatNumber(totalSettlements + totalCosts)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange[800])),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return _buildMobileExpenseTable(headers, rows);
            }
            return _buildDesktopExpenseTable(headers, rows);
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          ElevatedButton.icon(
            onPressed: _showAddSettlementDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('تسوية مورد'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showAddCostItemDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('مصروف'),
          ),
        ]),
      ],
    );
  }

  Widget _buildBreakdownExpensesTable() {
    final items = _breakdownResult.allItems;
    final headers = ['المنتج', 'البيان', 'الكمية', 'السعر', 'القيمة', 'اسم المورد', 'الفرز', 'ملاحظات'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.teal[50],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('بيان التكاليف من النظام (shipment_cost_breakdown)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal[800])),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            border: TableBorder.all(color: Colors.grey[300]!, width: 0.5),
            columns: headers.map((h) => DataColumn(
              label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            )).toList(),
            rows: items.map((item) {
              Color? bg;
              if (_breakdownResult.supplierItems.contains(item)) {
                bg = Colors.green[50];
              } else if (_breakdownResult.packingItems.contains(item)) {
                bg = Colors.blue[50];
              } else if (_breakdownResult.logisticsItems.contains(item)) {
                bg = Colors.orange[50];
              } else {
                bg = Colors.purple[50];
              }
              return DataRow(
                color: WidgetStateProperty.all(bg),
                cells: [
                  DataCell(Text(item.description, style: const TextStyle(fontSize: 12))),
                  DataCell(Text(item.categoryLabel, style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${item.quantity.toStringAsFixed(1)} ${item.unitLabel}', style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${item.unitCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}', style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${item.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal[800]))),
                  DataCell(Text(item.supplier ?? '—', style: const TextStyle(fontSize: 12))),
                  DataCell(Text(item.costCategory.isNotEmpty ? item.costCategory : '—', style: const TextStyle(fontSize: 12))),
                  DataCell(Text(item.notes ?? '—', style: const TextStyle(fontSize: 12))),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _breakdownChip('خامة', _breakdownResult.totalSupplierAmount, Colors.green),
            _breakdownChip('تعبئة', _breakdownResult.totalPackingCost, Colors.blue),
            _breakdownChip('لوجستيات', _breakdownResult.totalLogisticsCost, Colors.orange),
            _breakdownChip('إداري', _breakdownResult.totalAdminCost, Colors.purple),
            const SizedBox(width: 8),
            _breakdownChip('الإجمالي', _breakdownResult.grandTotalCost, Colors.teal, bold: true),
          ],
        ),
      ],
    );
  }

  Widget _breakdownChip(String label, double amount, MaterialColor color, {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label: ${AppUtils.formatNumber(amount)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
          style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color[800])),
    );
  }

  Widget _buildDesktopExpenseTable(List<String> headers, List<_ExpenseRow> rows) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headingBg = isDark ? Colors.grey[700] : Colors.grey[100];
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(headingBg),
        columnSpacing: 16,
        border: TableBorder.all(color: borderColor, width: 0.5),
        columns: headers.map((h) => DataColumn(
          label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        )).toList(),
        rows: rows.asMap().entries.map((entry) {
          final row = entry.value;
          return DataRow(
            color: WidgetStateProperty.all(
              row.isSettlement
                  ? (isDark ? Colors.green[900]!.withAlpha(40) : Colors.green[50])
                  : (isDark ? Colors.blue[900]!.withAlpha(40) : Colors.blue[50]),
            ),
            cells: [
              ...row.cells.map((c) => DataCell(Text(c, style: const TextStyle(fontSize: 12)))),
              DataCell(
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () {
                    if (row.isSettlement) {
                      _deleteSettlement(row.originalIndex);
                    } else {
                      _deleteCostItem(row.originalIndex);
                    }
                  },
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobileExpenseTable(List<String> headers, List<_ExpenseRow> rows) {
    return Column(
      children: rows.map((row) {
        final cells = row.cells;
        final color = row.isSettlement ? Colors.green[50] : Colors.blue[50];
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (var j = 0; j < headers.length; j++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Text('${headers[j]}: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      Expanded(child: Text(cells[j], style: const TextStyle(fontSize: 11), textAlign: TextAlign.end)),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Financial Summary ──

  Widget _buildFinancialSummary() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850]! : const Color(0xFFF5F5F5);
    final validation = _validateProfit();

    return Card(
      elevation: 3,
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Validation warnings
            if (validation.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber[100],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber[400]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.warning_amber, size: 16, color: Colors.amber),
                      SizedBox(width: 4),
                      Text('تحذيرات قبل الطباعة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber)),
                    ]),
                    const SizedBox(height: 4),
                    for (final v in validation)
                      Text('• $v', style: const TextStyle(fontSize: 11, color: Colors.brown)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                const Text('ملخص مالي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_grandTotalCost > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _roi >= 0 ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('ROI: ${_roi.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                            color: _roi >= 0 ? Colors.green[800] : Colors.red[800])),
                  ),
              ],
            ),
            const Divider(),
            _buildCostBreakdown(),
            const Divider(thickness: 2),
            _summaryRow('إجمالي التكلفة', _grandTotalCost, Colors.red),
            _summaryRow('إجمالي الإيراد', _totalRevenue, Colors.green),
            const Divider(thickness: 2),
            _summaryRow('صافي الربح', _netProfit, _netProfit >= 0 ? Colors.green : Colors.red, bold: true, fontSize: 16),
            _summaryRow('هامش الربح', _profitMargin, Colors.black87, isPercent: true),
          ],
        ),
      ),
    );
  }

  List<String> _validateProfit() {
    final warnings = <String>[];
    if (_totalRevenue <= 0) warnings.add('⚠️ إجمالي الإيراد = 0 — يرجى التأكد من سعر البيع');
    if (_grandTotalCost <= 0) warnings.add('⚠️ إجمالي التكلفة = 0 — لم يتم إضافة أي مصروفات');
    if (_netProfit < 0) warnings.add('⚠️ صافي الربح سالب (${AppUtils.formatNumber(_netProfit)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}) — يرجى مراجعة الأسعار والتكاليف');

    if (!_useBreakdown) {
      if (_settlements.isEmpty) warnings.add('⚠️ لا توجد تسويات موردين');
      if (_costItems.isEmpty) warnings.add('⚠️ لا توجد مصروفات مركز تحضير');
    } else {
      if (_breakdownResult.totalSupplierAmount <= 0) {
        warnings.add('⚠️ لا توجد تكلفة خام في breakdown');
      }
      if (_breakdownResult.totalPackingCost <= 0 &&
          _breakdownResult.totalLogisticsCost <= 0 &&
          _breakdownResult.totalAdminCost <= 0) {
        warnings.add('⚠️ لا توجد مصروفات في breakdown');
      }
    }

    // Check revenue mismatch between shipment items and shipment total
    if (_shipmentItems.isNotEmpty) {
      final itemsTotal = _shipmentItems.fold<double>(0.0, (s, i) =>
          s + (double.tryParse(i['amount']?.toString() ?? '0') ?? 0));
      if (itemsTotal > 0 && _totalRevenue > 0) {
        final diff = (_totalRevenue - itemsTotal).abs();
        if (diff > 1.0) {
          warnings.add('⚠️ تباين في الإيراد: إجمالي المنتجات ($itemsTotal ${AppUtils.currencySymbol(_shipment!.currencyCode)}) يختلف عن إيراد الشحنة (${_totalRevenue} ${AppUtils.currencySymbol(_shipment!.currencyCode)}) بفارق ${diff.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}');
        }
      }
    }

    return warnings;
  }

  Widget _buildCostBreakdown() {
    final supplierAmount = _totalSupplierAmount;
    final packingCost = _totalPackingCost;
    final logisticsCost = _totalLogisticsCost;
    final adminCost = _totalAdminCost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('تفصيل التكاليف:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          if (_useBreakdown)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('مصدر موحد',
                  style: TextStyle(fontSize: 10, color: Colors.teal[700], fontWeight: FontWeight.bold)),
            ),
        ]),
        const SizedBox(height: 4),
        if (supplierAmount > 0) _summaryRow('- تكلفة الخامة (الموردين)', supplierAmount, Colors.teal, fontSize: 12),
        if (packingCost > 0) _summaryRow('- تكلفة التعبئة والتغليف', packingCost, Colors.blue, fontSize: 12),
        if (logisticsCost > 0) _summaryRow('- تكاليف لوجستية', logisticsCost, Colors.orange, fontSize: 12),
        if (adminCost > 0) _summaryRow('- مصروفات إدارية', adminCost, Colors.purple, fontSize: 12),
      ],
    );
  }

  Widget _summaryRow(String label, double amount, Color color,
      {bool bold = false, double fontSize = 14, bool isPercent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: fontSize)),
          const Spacer(),
          Text(
            isPercent ? '${amount.toStringAsFixed(2)}%' : '${AppUtils.formatNumber(amount)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: fontSize, color: color),
          ),
        ],
      ),
    );
  }

  // ── Recipe Consumption Card ──

  Widget _buildRecipeConsumptionCard() {
    final recipeName = _recipeSnapshots.first.recipeName ?? '—';
    final recipeVersion = _recipeSnapshots.first.recipeVersion;
    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Text('المواد المستهلكة (حسب وصفات التعبئة)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('الوصفة: $recipeName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 24),
                  Text('إصدار: $recipeVersion',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 24),
                  Text('إجمالي الكراتين: $_totalCartons',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 24),
                  Text('التكلفة: ${AppUtils.formatNumber(_recipeTotalCost)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue[700])),
                ]),
                const SizedBox(height: 4),
                Text('(${_recipeSnapshots.length} مادة) — تم حفظ snapshot عند إنشاء الشحنة',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
                _dataTable(
                  ['المادة', 'الوحدة', 'لكل كرتونة', 'سعر الوحدة', 'الإجمالي المطلوب', 'التكلفة'],
                  _recipeSnapshots.map((r) => [
                    r.materialName ?? '—',
                    r.unit ?? '—',
                    r.quantityPerCarton.toStringAsFixed(2),
                    r.unitCost > 0 ? '${r.unitCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}' : '—',
                    '${r.totalQuantity.toStringAsFixed(1)} ${r.unit ?? ''}',
                    r.unitCost > 0 ? '${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(_shipment!.currencyCode)}' : '—',
                  ]).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Data Table ──

  Widget _dataTable(List<String> headers, List<List<String>> rows,
      {Function(int)? onDelete, List<String>? footerRow}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headingBg = isDark ? Colors.grey[700] : Colors.grey[100];
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _buildMobileTable(headers, rows, onDelete: onDelete);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(headingBg),
            columnSpacing: 16,
            border: TableBorder.all(color: borderColor, width: 0.5),
            columns: headers.map((h) => DataColumn(
              label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            )).toList(),
            rows: [
              ...rows.asMap().entries.map((entry) {
                final i = entry.key;
                final cells = entry.value;
                return DataRow(
                  cells: [
                    ...cells.map((c) => DataCell(Text(c, style: const TextStyle(fontSize: 12)))),
                    if (onDelete != null)
                      DataCell(IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        onPressed: () => onDelete(i),
                      )),
                  ],
                );
              }),
              if (footerRow != null)
                DataRow(
                  color: WidgetStateProperty.all(isDark ? Colors.grey[800] : Colors.grey[100]),
                  cells: footerRow.map((c) => DataCell(
                    Text(c, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  )).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileTable(List<String> headers, List<List<String>> rows,
      {Function(int)? onDelete}) {
    return Column(
      children: rows.asMap().entries.map((entry) {
        final i = entry.key;
        final cells = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              for (var j = 0; j < headers.length; j++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Text('${headers[j]}: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      Expanded(child: Text(cells[j], style: const TextStyle(fontSize: 11), textAlign: TextAlign.end)),
                    ],
                  ),
                ),
              if (onDelete != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () => onDelete(i),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Auto Generate ──

  Future<void> _autoGenerate() async {
    try {
      final warnings = _validateProfit();
      if (warnings.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تحذير'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('يوجد ملاحظات على البيانات:'),
                  const SizedBox(height: 8),
                  for (final w in warnings)
                    Text('• $w', style: const TextStyle(color: Colors.red, fontSize: 12)),
                  const SizedBox(height: 8),
                  const Text('هل تريد المتابعة؟'),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
              ],
            ),
          ),
        );
        if (proceed != true) return;
      }
      await _autoPopulate.autoGenerate(widget.shipmentId.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم التوليد التلقائي بنجاح')),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ خطأ في التوليد التلقائي: $e')),
      );
    }
  }

  // ── PDF ──

  Future<void> _printPdf() async {
    try {
      await PrepCenterInvoicePdfService.previewPdf(
        context: context,
        shipment: _shipment!,
        shipmentItems: _shipmentItems,
        settlements: _settlements,
        costItems: _costItems,
        packingOrders: _packingOrders,
        recipes: _recipeSnapshots,
        breakdownResult: _breakdownResult,
        profitabilityResult: _profitResult,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ فشل إنشاء PDF: $e')),
      );
    }
  }

  // ── CRUD ──

  Future<void> _deleteSettlement(int index) async {
    if (index >= _settlements.length) return;
    final item = _settlements[index];
    if (item.id == null) return;
    try {
      await _settlementDao.delete(item.id!.toString());
      _settlements.removeAt(index);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ فشل الحذف: $e')));
    }
  }

  Future<void> _deleteCostItem(int index) async {
    if (index >= _costItems.length) return;
    final item = _costItems[index];
    if (item.id == null) return;
    try {
      await _costItemDao.delete(item.id!.toString());
      _costItems.removeAt(index);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ فشل الحذف: $e')));
    }
  }

  void _showAddSettlementDialog() {
    String? selectedSupplierId;
    String? selectedProductId;
    String grade = 'A';
    final weightController = TextEditingController();
    final priceController = TextEditingController();
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة تسوية مورد'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'المورد'),
                    items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.displayName))).toList(),
                    onChanged: (v) => selectedSupplierId = v,
                    validator: (v) => v == null ? 'اختر المورد' : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'المنتج'),
                    items: _productItems.map((p) => DropdownMenuItem<String>(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (v) { selectedProductId = v; },
                    validator: (v) => v == null ? 'اختر المنتج' : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'الفرز'),
                    initialValue: grade,
                    items: ['A','B','C','waste'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (v) { if (v != null) grade = v; },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: weightController,
                    decoration: const InputDecoration(labelText: 'الكمية (كجم)'),
                    keyboardType: TextInputType.number,
                    validator: (v) { final val = double.tryParse(v ?? ''); if (val == null || val <= 0) return 'أدخل كمية صحيحة'; return null; },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                    keyboardType: TextInputType.number,
                    validator: (v) { final val = double.tryParse(v ?? ''); if (val == null || val < 0) return 'أدخل سعراً صحيحاً'; return null; },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'ملاحظات'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (selectedSupplierId == null || selectedProductId == null) return;
                Navigator.pop(ctx);
                final selectedItem = _productItems.firstWhereOrNull((p) => p.id == selectedProductId);
                final item = SupplierSettlementModel(
                  shipmentId: widget.shipmentId,
                  supplierId: selectedSupplierId!,
                  productId: int.tryParse(selectedProductId!) ?? 0,
                  grade: grade,
                  weightKg: double.tryParse(weightController.text) ?? 0,
                  unitPrice: double.tryParse(priceController.text) ?? 0,
                  notes: notesController.text.isNotEmpty ? notesController.text : null,
                  supplierName: _suppliers.firstWhere((s) => s.id == selectedSupplierId).name,
                  productName: selectedItem?.name ?? '',
                );
                try { await _settlementDao.insert(item); } catch (e) { debugPrint('⚠️ prep_center: Failed to insert settlement item: $e'); }
                _loadData();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCostItemDialog() {
    String costType = 'OTHER';
    final descController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController();
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة مصروف'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'نوع المصروف'),
                    initialValue: costType,
                    items: PrepCenterCostItemModel.costTypes.map((t) => DropdownMenuItem(value: t, child: Text(_costTypeLabel(t)))).toList(),
                    onChanged: (v) { if (v != null) costType = v; },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'البيان'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل بيان المصروف' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: qtyController,
                    decoration: const InputDecoration(labelText: 'الكمية'),
                    keyboardType: TextInputType.number,
                    validator: (v) { final val = double.tryParse(v ?? ''); if (val == null || val <= 0) return 'أدخل كمية صحيحة'; return null; },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                    keyboardType: TextInputType.number,
                    validator: (v) { final val = double.tryParse(v ?? ''); if (val == null || val < 0) return 'أدخل سعراً صحيحاً'; return null; },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'ملاحظات'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(ctx);
                final item = PrepCenterCostItemModel(
                  shipmentId: widget.shipmentId,
                  costType: costType,
                  description: descController.text,
                  qty: double.tryParse(qtyController.text) ?? 1,
                  unitPrice: double.tryParse(priceController.text) ?? 0,
                  notes: notesController.text.isNotEmpty ? notesController.text : null,
                );
                try { await _costItemDao.insert(item); } catch (e) { debugPrint('⚠️ prep_center: Failed to insert cost item: $e'); }
                _loadData();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  String _costTypeLabel(String type) {
    switch (type) {
      case 'PACKAGING': return 'تعبئة وتغليف';
      case 'LABOR': return 'عمالة';
      case 'DIESEL': return 'ديزل';
      case 'AGRICULTURE': return 'أجرة زراعية';
      case 'TRANSPORT': return 'نقل';
      case 'COOLING': return 'تبريد';
      case 'LABELS': return 'ليبل';
      case 'STICKERS': return 'استيكر';
      default: return 'أخرى';
    }
  }

  String _d(dynamic v) {
    if (v == null) return '0.00';
    if (v is double) return v.toStringAsFixed(2);
    if (v is num) return v.toDouble().toStringAsFixed(2);
    final parsed = double.tryParse(v.toString());
    return parsed?.toStringAsFixed(2) ?? '0.00';
  }
}

class _ExpenseRow {
  final int originalIndex;
  final List<String> cells;
  final bool isSettlement;
  const _ExpenseRow({required this.originalIndex, required this.cells, required this.isSettlement});
}
