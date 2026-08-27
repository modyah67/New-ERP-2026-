import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/utils.dart';
import '../../data/dao/shipment_cost_breakdown_dao.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/models/shipment_cost_breakdown_model.dart';
import '../../data/models/export_shipment_model.dart';
import 'shipment_invoice_pdf_service.dart';
import 'shipment_cost_breakdown_page.dart';

class ShipmentInvoicePreviewPage extends StatefulWidget {
  final int shipmentId;
  const ShipmentInvoicePreviewPage({super.key, required this.shipmentId});

  @override
  State<ShipmentInvoicePreviewPage> createState() =>
      _ShipmentInvoicePreviewPageState();
}

class _ShipmentInvoicePreviewPageState
    extends State<ShipmentInvoicePreviewPage> {
  final _exportDao = ExportShipmentDao();
  final _breakdownDao = ShipmentCostBreakdownDao();
  final _itemsDao = ExportShipmentItemDao();
  ExportShipmentModel? _shipment;
  List<ShipmentCostBreakdownModel> _breakdown = [];
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final results = await Future.wait([
        _exportDao.getById(widget.shipmentId),
        _breakdownDao.getForShipment(widget.shipmentId.toString()),
        _itemsDao.getByShipmentId(widget.shipmentId),
      ]);
      if (mounted) {
        setState(() {
          _shipment = results[0] as ExportShipmentModel?;
          _breakdown = results[1] as List<ShipmentCostBreakdownModel>;
          _items = results[2] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.background,
                Color(0xFF0D2137),
                AppTheme.background,
              ],
            ),
          ),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : _error
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
                          const SizedBox(height: 12),
                          const Text('حدث خطأ أثناء تحميل البيانات',
                              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _load,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.primary.withAlpha(60)),
                              ),
                              child: const Text('إعادة المحاولة',
                                  style: TextStyle(color: AppTheme.primary, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _shipment == null
                      ? const Center(
                          child: Text('لم يتم العثور على الشحنة',
                              style: TextStyle(color: AppTheme.textSecondary)))
                      : Column(children: [
                          _buildHeader(),
                          Expanded(child: _buildPreview()),
                        ]),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 16,
              left: 20,
              right: 20),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(
                bottom:
                    BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withAlpha(60)),
                ),
                child: const Icon(Icons.arrow_forward,
                    color: AppTheme.primary, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.picture_as_pdf, color: AppTheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text('فاتورة — ${_shipment!.shipmentNo}',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
            GestureDetector(
              onTap: _printPdf,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.success.withAlpha(60)),
                ),
                child: const Icon(Icons.print, color: AppTheme.success, size: 22),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShipmentCostBreakdownPage(
                      shipmentId: widget.shipmentId),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warning.withAlpha(60)),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: AppTheme.warning, size: 22),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _printPdf() async {
    await ShipmentInvoicePdfService.previewPdf(
      context: context,
      shipment: _shipment!,
      breakdown: _breakdown,
      itemsData: _items,
    );
  }

  Widget _buildPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildInfoCard(),
        const SizedBox(height: 16),
        _buildSummaryBar(),
        const SizedBox(height: 16),
        _buildExportedProductsSection(),
        const SizedBox(height: 16),
        _buildRawMaterialsSection(),
        const SizedBox(height: 16),
        _buildOperationsSection(),
        const SizedBox(height: 16),
        _buildFinancialSummary(),
        const SizedBox(height: 16),
        _buildSupplierTags(),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ── Section 1: Shipment Info ──

  Widget _buildInfoCard() {
    final s = _shipment!;
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 60, child: Text('رقم الشحنة',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
          Expanded(child: UIUtils.shipmentNoText(s.shipmentNo,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
          const SizedBox(width: 40, child: Text('التاريخ',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
          Text(s.shipmentDate != null ? AppUtils.formatDate(s.shipmentDate!) : '—',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ]),
        const Divider(color: AppTheme.glassBorder, height: 16),
        Row(children: [
          const SizedBox(width: 60, child: Text('العميل',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
          Expanded(child: Text(s.customerName ?? '—',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
          const SizedBox(width: 40, child: Text('الوجهة',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
          Text(s.country ?? '—',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ]),
        const Divider(color: AppTheme.glassBorder, height: 16),
        Row(children: [
          const SizedBox(width: 60, child: Text('الحاوية',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
          Expanded(child: Text(s.containerNo ?? '—',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
          const SizedBox(width: 40, child: Text('الوزن',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
          Text('${s.netWeight} كجم',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ]),
      ]),
    );
  }

  // ── Top Summary Bar ──

  Widget _buildSummaryBar() {
    final s = _shipment!;
    final fruitItems = _breakdown.where((r) => r.costType == 'fruit').toList();
    final fruitTotal = fruitItems.fold<double>(0.0, (s, r) => s + r.totalCost);
    final otherCostTypes = ['packing_material', 'logistics', 'export_cost', 'admin', 'other'];
    final opItems = _breakdown.where((r) => otherCostTypes.contains(r.costType)).toList();
    final opTotal = opItems.fold<double>(0.0, (s, r) => s + r.totalCost);
    final grandTotal = fruitTotal + opTotal;

    return Row(children: [
      Expanded(child: _statCard(Icons.inventory_2, '${s.cartonsCount}', 'كرتونة', const Color(0xFF10B981))),
      const SizedBox(width: 8),
      Expanded(child: _statCard(Icons.agriculture, '${AppUtils.formatNumber(fruitTotal)}', 'خام', const Color(0xFF8B5CF6))),
      const SizedBox(width: 8),
      Expanded(child: _statCard(Icons.attach_money, '${AppUtils.formatNumber(grandTotal)}', 'جنيه', const Color(0xFF3B82F6))),
    ]);
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo')),
      ]),
    );
  }

  // ── Section 2: Exported Products ──

  Widget _buildExportedProductsSection() {
    if (_items.isEmpty) return const SizedBox.shrink();
    final totalCartons = _items.fold<int>(0, (s, i) => s + (int.tryParse(i['quantity']?.toString() ?? '0') ?? 0));

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _sectionHeader('المنتجات المُصدَّرة', Icons.inventory_2, AppTheme.primary),
        const SizedBox(height: 12),
        _tableHeader(['المنتج', 'عدد الكراتين', 'الوزن (كجم)']),
        ..._items.asMap().entries.map((e) {
          final item = e.value;
          final productName = item['product_name']?.toString() ?? item['name']?.toString() ?? '—';
          final qty = item['quantity']?.toString() ?? '0';
          final weightPerCarton = item['weight_per_carton']?.toString() ?? item['weightPerCarton']?.toString() ?? '—';
          final label = weightPerCarton != '—' ? '$weightPerCarton كجم' : '—';
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(flex: 3, child: Text(productName,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 1, child: Text(qty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 1, child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
            ]),
          );
        }),
        const Divider(color: AppTheme.glassBorder),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            const Expanded(flex: 3,
                child: Text('الإجمالي',
                    style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
            Expanded(flex: 1,
                child: Text('$totalCartons',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
            const Expanded(flex: 1, child: SizedBox()),
          ]),
        ),
      ]),
    );
  }

  // ── Section 3: Raw Materials ──

  Widget _buildRawMaterialsSection() {
    final fruitItems = _breakdown.where((r) => r.costType == 'fruit').toList();
    if (fruitItems.isEmpty) return const SizedBox.shrink();
    final fruitTotal = fruitItems.fold<double>(0.0, (s, r) => s + r.totalCost);

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _sectionHeader('الخامات', Icons.agriculture, const Color(0xFF10B981)),
        const SizedBox(height: 12),
        _tableHeader(['المنتج', 'الكمية', 'السعر', 'القيمة', 'المورد']),
        ...fruitItems.map((r) {
          final cur = r.currency == 'USD' ? '\$' : 'ج.م';
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(flex: 2, child: Text(r.itemName,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 1,
                  child: Text('${r.quantity.toStringAsFixed(1)} كجم',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 1,
                  child: Text('$cur ${r.unitCost.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 1,
                  child: Text('$cur ${r.totalCost.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
              Expanded(flex: 1,
                  child: Text(r.supplier ?? '—',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.primaryLight, fontSize: 12, fontFamily: 'Cairo'))),
            ]),
          );
        }),
        const Divider(color: AppTheme.glassBorder),
        _totalRow('إجمالي الخام', '${AppUtils.formatNumber(fruitTotal)} ج.م', AppTheme.primary),
      ]),
    );
  }

  // ── Section 4: Operations & Expenses ──

  Widget _buildOperationsSection() {
    final otherCostTypes = ['packing_material', 'logistics', 'export_cost', 'admin', 'other'];
    final opItems = _breakdown.where((r) => otherCostTypes.contains(r.costType)).toList();
    if (opItems.isEmpty) return const SizedBox.shrink();
    final opTotal = opItems.fold<double>(0.0, (s, r) => s + r.totalCost);
    final showQty = opItems.any((r) => r.quantity > 0);

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _sectionHeader('مصروفات التشغيل والتعبئة والنقل', Icons.settings, const Color(0xFF3B82F6)),
        const SizedBox(height: 12),
        _tableHeader(showQty ? ['البيان', 'الكمية', 'القيمة'] : ['البيان', '', 'القيمة']),
        ...opItems.map((r) {
          final cur = r.currency == 'USD' ? '\$' : 'ج.م';
          final typeColors = {
            'packing_material': const Color(0xFF3B82F6),
            'logistics': const Color(0xFFF59E0B),
            'export_cost': const Color(0xFF8B5CF6),
            'admin': const Color(0xFFEC4899),
            'other': Colors.grey,
          };
          final labelColors = {
            'packing_material': const Color(0xFF60A5FA),
            'logistics': const Color(0xFFFBBF24),
            'export_cost': const Color(0xFFA78BFA),
            'admin': const Color(0xFFF472B6),
            'other': Colors.grey,
          };
          final labelColor = labelColors[r.costType] ?? Colors.grey;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(flex: 3,
                  child: Row(children: [
                    Container(
                      width: 4, height: 14,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: labelColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(r.itemName,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo')),
                  ])),
              if (showQty)
                Expanded(flex: 1,
                    child: Text(r.quantity > 0 ? r.quantity.toStringAsFixed(1) : '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 1,
                  child: Text('$cur ${r.totalCost.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: typeColors[r.costType] ?? Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
            ]),
          );
        }),
        const Divider(color: AppTheme.glassBorder),
        _totalRow('إجمالي المصروفات', '${AppUtils.formatNumber(opTotal)} ج.م', const Color(0xFF3B82F6)),
      ]),
    );
  }

  // ── Section 5: Financial Summary ──

  Widget _buildFinancialSummary() {
    final fruitItems = _breakdown.where((r) => r.costType == 'fruit').toList();
    final fruitTotal = fruitItems.fold<double>(0.0, (s, r) => s + r.totalCost);
    final otherCostTypes = ['packing_material', 'logistics', 'export_cost', 'admin', 'other'];
    final opItems = _breakdown.where((r) => otherCostTypes.contains(r.costType)).toList();
    final opTotal = opItems.fold<double>(0.0, (s, r) => s + r.totalCost);
    final grandTotal = fruitTotal + opTotal;

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: const Color(0xFF00c896), width: 3)),
          ),
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: const Row(children: [
            Icon(Icons.summarize, color: AppTheme.primary, size: 18),
            SizedBox(width: 8),
            Text('الملخص المالي',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _summaryRow('إجمالي الخام', '${AppUtils.formatNumber(fruitTotal)} ج.م', Colors.white),
            const Divider(color: AppTheme.glassBorder, height: 16),
            _summaryRow('إجمالي المصروفات', '${AppUtils.formatNumber(opTotal)} ج.م', Colors.white),
            const Divider(color: AppTheme.glassBorder, height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF00c896).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _summaryRow('إجمالي تكلفة الشحنة', '${AppUtils.formatNumber(grandTotal)} ج.م', const Color(0xFF00c896),
                  bold: true, large: true),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Section 6: Supplier Tags ──

  Widget _buildSupplierTags() {
    final suppliers = _breakdown
        .where((r) => r.supplier != null && r.supplier!.trim().isNotEmpty)
        .map((r) => r.supplier!)
        .toSet()
        .toList();
    if (suppliers.isEmpty) return const SizedBox.shrink();

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const Row(children: [
          Icon(Icons.people, color: AppTheme.primary, size: 18),
          SizedBox(width: 8),
          Text('الموردون',
              style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suppliers.map((s) => Chip(
            label: Text(s,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFF1a2332),
            side: const BorderSide(color: Color(0xFF00c896)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          )).toList(),
        ),
      ]),
    );
  }

  // ── Shared Widgets ──

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: const Color(0xFF00c896), width: 3)),
      ),
      padding: const EdgeInsetsDirectional.only(start: 12),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const Spacer(),
      ]),
    );
  }

  Widget _tableHeader(List<String> cols) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: cols.map((c) => Expanded(
        flex: cols.length == 3 ? 1 : cols.indexOf(c) == 0 ? 2 : 1,
        child: Text(c,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
      )).toList()),
    );
  }

  Widget _totalRow(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        Expanded(flex: 3,
            child: Text(label,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
        const Spacer(),
        Text(value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ]),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool bold = false, bool large = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: large ? 15 : 13,
                fontFamily: 'Cairo',
                fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        const Spacer(),
        Text(value,
            style: TextStyle(
              color: color,
              fontSize: large ? 18 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontFamily: 'Cairo',
            )),
      ]),
    );
  }
}
