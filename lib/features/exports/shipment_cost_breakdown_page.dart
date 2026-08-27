import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/utils.dart';
import '../../core/services/shipment_profitability_service.dart';
import '../../data/dao/shipment_cost_breakdown_dao.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/models/shipment_cost_breakdown_model.dart';
import '../../data/models/export_shipment_model.dart';
import 'shipment_cost_sheet_pdf_service.dart';

class ShipmentCostBreakdownPage extends StatefulWidget {
  final int shipmentId;
  const ShipmentCostBreakdownPage({super.key, required this.shipmentId});

  @override
  State<ShipmentCostBreakdownPage> createState() =>
      _ShipmentCostBreakdownPageState();
}

class _ShipmentCostBreakdownPageState
    extends State<ShipmentCostBreakdownPage> {
  final _dao = ShipmentCostBreakdownDao();
  final _exportDao = ExportShipmentDao();
  final _profitabilityService = ShipmentProfitabilityService();
  List<ShipmentCostBreakdownModel> _rows = [];
  ExportShipmentModel? _shipment;
  ShipmentProfitabilityResult? _result;
  bool _loading = true;
  bool _canExportPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
    _checkRole();
  }

  Future<void> _checkRole() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('is_admin')
          .eq('id', userId)
          .maybeSingle();
      if (profile != null && profile['is_admin'] == true) {
        if (mounted) setState(() => _canExportPdf = true);
        return;
      }
      final userRole = await Supabase.instance.client
          .from('user_roles')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
      if (userRole != null) {
        final role = userRole['role'] as String?;
        if (ShipmentCostSheetPdfService.hasAccess(role)) {
          if (mounted) setState(() => _canExportPdf = true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _canExportPdf = true);
    }
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _dao.getForShipment(widget.shipmentId.toString()),
        _exportDao.getById(widget.shipmentId),
        _profitabilityService.calculateShipment(widget.shipmentId.toString()),
      ]);
      if (mounted) setState(() { 
        _rows = results[0] as List<ShipmentCostBreakdownModel>; 
        _shipment = results[1] as ExportShipmentModel?; 
        _result = results[2] as ShipmentProfitabilityResult?;
        _loading = false; 
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
              : Column(children: [
                  _buildHeader(),
                  Expanded(child: _buildContent()),
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
            const Icon(Icons.calculate_outlined,
                color: AppTheme.primary, size: 24),
            const SizedBox(width: 12),
            const Text('مركز التسعير الداخلي',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            const Spacer(),
            if (_canExportPdf) ...[
              GestureDetector(
                onTap: _exportPdf,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.emerald.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.emerald.withAlpha(60)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.picture_as_pdf,
                        color: AppTheme.emerald, size: 18),
                    SizedBox(width: 4),
                    Text('PDF',
                        style: TextStyle(
                            color: AppTheme.emerald,
                            fontSize: 12,
                            fontFamily: 'Cairo')),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    try {
      final shipment = _shipment ?? await _exportDao.getById(widget.shipmentId);
      if (shipment == null || !mounted) return;
      await ShipmentCostSheetPdfService.previewPdf(
        context: context,
        shipment: shipment,
        breakdown: _rows,
        profitabilityResult: _result,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء ملف PDF: $e')),
        );
      }
    }
  }

  Widget _buildContent() {
    if (_rows.isEmpty && _shipment == null) {
      return const Center(
        child: Text('لا توجد بيانات تكلفة',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        if (_shipment != null) ...[
          _buildShipmentInfo(),
          const SizedBox(height: 16),
        ],
        ..._buildTypeSection('fruit', const Color(0xFF10B981), Icons.agriculture),
        const SizedBox(height: 12),
        ..._buildTypeSection('packing_material', const Color(0xFF3B82F6), Icons.inventory_2),
        const SizedBox(height: 12),
        ..._buildTypeSection('logistics', const Color(0xFFF59E0B), Icons.local_shipping),
        const SizedBox(height: 12),
        ..._buildTypeSection('export_cost', const Color(0xFF8B5CF6), Icons.flight),
        const SizedBox(height: 12),
        ..._buildTypeSection('admin', const Color(0xFFEC4899), Icons.admin_panel_settings),
        const SizedBox(height: 12),
        ..._buildTypeSection('other', Colors.grey, Icons.more_horiz),
        const SizedBox(height: 16),
        _buildGrandTotal(),
        const SizedBox(height: 16),
        _buildKpiRow(),
        const SizedBox(height: 16),
        _buildProfitSection(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _buildShipmentInfo() {
    final s = _shipment!;
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          _infoChip(Icons.tag, s.shipmentNo, AppTheme.primary),
          const SizedBox(width: 8),
          _infoChip(Icons.person, s.customerName ?? '-', AppTheme.emerald),
          const Spacer(),
          _statusChip(s.status),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _infoChip(Icons.location_on, '${s.country ?? '-'} / ${s.portOfDestination ?? '-'}', AppTheme.warning),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (s.vesselName != null)
            _infoChip(Icons.directions_boat, s.vesselName!, const Color(0xFF22D3EE)),
          if (s.containerNo != null) ...[
            const SizedBox(width: 8),
            _infoChip(Icons.inventory, s.containerNo!, const Color(0xFF8B5CF6)),
          ],
          if (s.incoterm != null) ...[
            const SizedBox(width: 8),
            _infoChip(Icons.local_offer, s.incoterm!, const Color(0xFFF59E0B)),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _infoChip(Icons.local_shipping, '${s.cartonsCount} كرتونة', AppTheme.textSecondary),
          const SizedBox(width: 8),
          _infoChip(Icons.monetization_on, '${s.exportPricePerCarton.toStringAsFixed(2)} ${s.currencyCode}/كرتونة', AppTheme.textSecondary),
          if (s.shipmentDate != null) ...[
            const SizedBox(width: 8),
            _infoChip(Icons.calendar_today, _fmtDate(s.shipmentDate!), AppTheme.textSecondary),
          ],
        ]),
      ]),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Directionality(textDirection: TextDirection.ltr, child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontFamily: 'Cairo'))),
      ]),
    );
  }

  Widget _statusChip(String status) {
    final Color c;
    switch (status) {
      case 'pending': c = AppTheme.warning; break;
      case 'in_transit': c = AppTheme.primary; break;
      case 'shipped': c = AppTheme.emerald; break;
      case 'cancelled': c = AppTheme.danger; break;
      default: c = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withAlpha(60)),
      ),
      child: Text(status,
          style: TextStyle(
              color: c, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  List<Widget> _buildTypeSection(String type, Color color, IconData icon) {
    final items = _rows.where((r) => r.costType == type).toList();
    if (items.isEmpty) return [];
    final typeTotal =
        items.fold<double>(0.0, (s, r) => s + r.totalCost);

    return [
      AppTheme.glassCardWidget(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Text(items.first.costTypeLabel,
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            const Spacer(),
            Text('${typeTotal.toStringAsFixed(2)} ج.م',
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ]),
          const SizedBox(height: 8),
          if (type == 'fruit')
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                const Expanded(flex: 3, child: SizedBox()),
                const SizedBox(
                  width: 80,
                  child: Text('المورد',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontFamily: 'Cairo')),
                ),
                const SizedBox(
                  width: 70,
                  child: Text('الوزن',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontFamily: 'Cairo')),
                ),
                const SizedBox(
                  width: 80,
                  child: Text('سعر الوحدة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontFamily: 'Cairo')),
                ),
                const SizedBox(
                  width: 80,
                  child: Text('الإجمالي',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontFamily: 'Cairo')),
                ),
              ]),
            ),
          ...items.map((r) => _buildRow(r, color)),
        ]),
      ),
    ];
  }

  Widget _buildRow(ShipmentCostBreakdownModel row, Color color) {
    final cur = AppUtils.currencySymbol(row.currency ?? 'EGP');
    final isFruit = row.costType == 'fruit';
    return GestureDetector(
      onTap: isFruit ? () => _editSupplier(row) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Text(row.itemName,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontFamily: 'Cairo')),
          ),
          if (isFruit)
            SizedBox(
              width: 80,
              child: Text(row.supplier ?? '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: row.supplier != null ? AppTheme.primaryLight : AppTheme.textSecondary,
                      fontSize: 11,
                      fontFamily: 'Cairo')),
            ),
          SizedBox(
            width: 70,
            child: Text(row.quantity.toStringAsFixed(1),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Cairo')),
          ),
          SizedBox(
            width: 80,
            child: Text('$cur ${row.unitCost.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Cairo')),
          ),
          SizedBox(
            width: 80,
            child: Text(row.totalCost.toStringAsFixed(2),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ),
          if (isFruit)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.edit, color: AppTheme.textSecondary, size: 14),
            ),
        ]),
      ),
    );
  }

  Future<void> _editSupplier(ShipmentCostBreakdownModel row) async {
    final supplierCtrl = TextEditingController(text: row.supplier ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xCC05192D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppTheme.glassBorder),
          ),
          title: Text('تعديل المورد — ${row.itemName}',
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          content: TextField(
            controller: supplierCtrl,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'اسم المورد',
              hintText: 'أدخل اسم المورد',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, supplierCtrl.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty || row.id == null) return;
    try {
      await _dao.updateSupplier(row.id!.toString(), result);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ المورد بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ المورد: $e')),
        );
      }
    }
  }

  Widget _buildGrandTotal() {
    final total = _rows.fold<double>(0.0, (s, r) => s + r.totalCost);
    final curCode = _shipment?.currencyCode ?? 'EGP';
    return AppTheme.glassCardWidget(
      child: Row(children: [
        const Text('الإجمالي الكلي',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontFamily: 'Cairo')),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(50)),
          ),
          child: Text('${AppUtils.currencySymbol(curCode)} ${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ),
      ]),
    );
  }

  Widget _buildKpiRow() {
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    final fruitTotal = r.fruitCost;
    final packingTotal = r.packingCost;
    final logisticsTotal = r.logisticsCost;
    final adminTotal = r.administrativeCost;
    final otherTotal = r.otherCost;

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const Text('مؤشرات الأداء',
            style: TextStyle(
                color: AppTheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        _kpiItem('تكلفة الفاكهة', fruitTotal, const Color(0xFF10B981)),
        const SizedBox(height: 6),
        _kpiItem('تكلفة التعبئة', packingTotal, const Color(0xFF3B82F6)),
        const SizedBox(height: 6),
        _kpiItem('تكلفة الخدمات اللوجستية', logisticsTotal,
            const Color(0xFFF59E0B)),
        const SizedBox(height: 6),
        _kpiItem('تكلفة إدارية', adminTotal, const Color(0xFFEC4899)),
        const SizedBox(height: 6),
        _kpiItem('تكاليف أخرى', otherTotal, Colors.grey),
      ]),
    );
  }

  Widget _kpiItem(String label, double value, Color color) {
    final curCode = _shipment?.currencyCode ?? 'EGP';
    return Row(children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontFamily: 'Cairo')),
      const Spacer(),
      Text('${AppUtils.currencySymbol(curCode)} ${value.toStringAsFixed(2)}',
          style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo')),
    ]);
  }


  Widget _buildProfitSection() {
    final s = _shipment;
    final r = _result;
    if (s == null || r == null) return const SizedBox.shrink();
    
    // All values from ShipmentProfitabilityService
    final totalCost = r.totalCost;
    final revForeign = r.revenueEur;
    final revEgp = r.revenueEgp;
    final netProfit = r.netProfit;
    final margin = r.netMargin;
    final costPerCarton = r.costPerCarton;
    final profitPerCarton = r.profitPerCarton;
    final symbol = AppUtils.currencySymbol(s.currencyCode ?? 'EGP');
    final profitColor = netProfit >= 0 ? AppTheme.emerald : AppTheme.danger;

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.trending_up, color: AppTheme.primary, size: 16),
          ),
          const SizedBox(width: 8),
          const Text('ملخص الإيرادات والربحية',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ]),
        const SizedBox(height: 14),
        _profitRow('إيرادات التصدير (خارجي)', '$symbol ${revForeign.toStringAsFixed(2)}', AppTheme.primary),
        const SizedBox(height: 6),
        _profitRow('إيرادات التصدير (ج.م)', 'ج.م ${revEgp.toStringAsFixed(2)}', AppTheme.primary),
        const SizedBox(height: 6),
        _profitRow('إجمالي التكاليف (ج.م)', 'ج.م ${totalCost.toStringAsFixed(2)}', AppTheme.warning),
        const SizedBox(height: 10),
        Container(height: 1, color: AppTheme.glassBorder.withAlpha(50)),
        const SizedBox(height: 10),
        _profitRow('صافي الربح', 'ج.م ${netProfit.toStringAsFixed(2)}', profitColor),
        const SizedBox(height: 6),
        _profitRow('هامش الربح', '${margin.toStringAsFixed(1)}%', profitColor),
        const SizedBox(height: 14),
        Container(height: 1, color: AppTheme.glassBorder.withAlpha(50)),
        const SizedBox(height: 10),
        _profitRow('تكلفة الكرتون', '$symbol ${costPerCarton.toStringAsFixed(2)}', AppTheme.textSecondary),
        const SizedBox(height: 6),
        _profitRow('ربح الكرتون', '$symbol ${profitPerCarton.toStringAsFixed(2)}', AppTheme.emerald),
      ]),
    );
  }

  Widget _profitRow(String label, String value, Color color) {
    return Row(children: [
      Text(label,
          style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontFamily: 'Cairo')),
      const Spacer(),
      Text(value,
          style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo')),
    ]);
  }
}
