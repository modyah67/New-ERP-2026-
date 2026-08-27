import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../core/auth_state_notifier.dart';
import '../../features/auth/auth_cubit.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/services/shipment_profitability_service.dart';
import '../../data/dao/shipment_cost_allocation_dao.dart';
import '../../data/dao/shipment_cost_item_dao.dart';
import '../../data/models/shipment_cost_allocation_model.dart';
import '../../data/models/shipment_cost_item_model.dart';
import '../../data/services/journal_entry_navigation_service.dart';

class ShipmentProfitabilityPage extends StatefulWidget {
  final int shipmentId;
  const ShipmentProfitabilityPage({super.key, required this.shipmentId});

  @override
  State<ShipmentProfitabilityPage> createState() =>
      _ShipmentProfitabilityPageState();
}

class _ShipmentProfitabilityPageState
    extends State<ShipmentProfitabilityPage> {
  final _profitabilityService = ShipmentProfitabilityService();
  final _allocationDao = ShipmentCostAllocationDao();
  final _costItemDao = ShipmentCostItemDao();
  ShipmentProfitabilityResult? _result;
  List<ShipmentCostAllocationModel> _allocations = [];
  List<ShipmentCostItemModel> _costItems = [];
  List<Map<String, dynamic>> _journalEntries = [];
  List<Map<String, dynamic>> _treasuries = [];
  List<Map<String, dynamic>> _bankAccounts = [];
  List<Map<String, dynamic>> _expenseAccounts = [];
  List<Map<String, dynamic>> _shippingCompanies = [];
  List<Map<String, dynamic>> _clearingAgents = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _allocationBasis = 'cartons';

  bool get _hideProfit {
    final authState = authNotifier.value;
    if (authState is AuthAuthenticated) {
      return !authState.isAdmin;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _error = null; });
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        _profitabilityService.calculateShipment(widget.shipmentId.toString()),
        _allocationDao.getForShipment(widget.shipmentId),
        _costItemDao.getForShipment(widget.shipmentId),
        _costItemDao.getJournalEntriesForShipment(widget.shipmentId),
        client.from('treasuries').select('id, name, treasury_balances(balance, currency)').order('name'),
        client.from('bank_accounts').select('id, name, balance, currency').order('name'),
        client.rpc('rpc_get_expense_leaf_accounts'),
        client.from('shipping_companies').select('id, name').order('name'),
        client.from('clearing_agents').select('id, name').order('name'),
      ]);
      if (mounted) {
        setState(() {
          _result = results[0] as ShipmentProfitabilityResult?;
          _allocations = results[1] as List<ShipmentCostAllocationModel>;
          _costItems = results[2] as List<ShipmentCostItemModel>;
          _journalEntries = List<Map<String, dynamic>>.from(results[3] as List);
          _treasuries = List<Map<String, dynamic>>.from(results[4] as List);
          _bankAccounts = List<Map<String, dynamic>>.from(results[5] as List);
          _expenseAccounts = List<Map<String, dynamic>>.from((results[6] as List).map((e) => Map<String, dynamic>.from(e as Map)));
          _shippingCompanies = List<Map<String, dynamic>>.from((results[7] as List).map((e) => Map<String, dynamic>.from(e as Map)));
          _clearingAgents = List<Map<String, dynamic>>.from((results[8] as List).map((e) => Map<String, dynamic>.from(e as Map)));
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: authNotifier,
      builder: (context, authState, _) {
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
                  : _result == null
                      ? const Center(
                          child: Text('لم يتم العثور على الشحنة',
                              style: TextStyle(color: AppTheme.textSecondary)))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 600;
                            return Column(children: [
                              _buildHeader(isNarrow),
                              Expanded(child: _buildContent(isNarrow)),
                            ]);
                          },
                        ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isNarrow) {
    final titleSize = isNarrow ? 14.0 : 18.0;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 12,
              left: isNarrow ? 12 : 20,
              right: isNarrow ? 12 : 20),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(
                bottom:
                    BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primary.withAlpha(60)),
                          ),
                          child: const Icon(Icons.arrow_forward,
                              color: AppTheme.primary, size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.analytics_outlined,
                            color: AppTheme.success, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('ربحية الشحنة',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: titleSize,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: UIUtils.shipmentNoText(_result!.shipmentNo,
                            style: TextStyle(
                                color: AppTheme.neonCyan,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                      const SizedBox(width: 8),
                      _headerIconBtn(Icons.print, AppTheme.info, () {}),
                      const SizedBox(width: 6),
                      _headerIconBtn(Icons.picture_as_pdf, AppTheme.danger, () {}),
                      const SizedBox(width: 6),
                      _headerIconBtn(Icons.add_circle_outline, AppTheme.success, () => _showAddExpenseSheet()),
                    ]),
                  ],
                )
              : Row(children: [
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.analytics_outlined,
                        color: AppTheme.success, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('تحليل ربحية — ${_result!.shipmentNo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                  const SizedBox(width: 8),
                  _headerIconBtn(Icons.print, AppTheme.info, () {}),
                  const SizedBox(width: 6),
                  _headerIconBtn(Icons.picture_as_pdf, AppTheme.danger, () {}),
                  const SizedBox(width: 6),
                  _headerIconBtn(Icons.add_circle_outline, AppTheme.success, () => _showAddExpenseSheet()),
                ]),
        ),
      ),
    );
  }

  Widget _headerIconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  String get _currencySymbol => _result!.currencyCode == 'EGP' ? 'ج.م' : '\$';
  String get _currencyCode => _result!.currencyCode;

  double get _revenueFgnEffective => _result!.revenueEur;
  double get _revenueEgpEffective => _result!.revenueEgp;
  double get _fruitTotal => _result!.fruitCost;
  double get _packingTotal => _result!.packingCost;
  double get _logisticsTotal => _result!.logisticsCost;
  double get _adminTotal => _result!.administrativeCost;
  double get _otherTotal => _result!.otherCost;
  double get _totalEgp => _result!.totalCost;
  double get _grossProfit => _result!.grossProfit;
  double get _netProfit => _result!.netProfit;
  double get _costPerCarton => _result!.costPerCarton;
  double get _revPerCarton => _result!.revenuePerCarton;
  double get _profitMargin => _result!.netMargin;
  double get _costPerKg => _result!.costPerKg;
  double get _revenuePerKg => _result!.revenuePerKg;
  double get _profitPerKg => _result!.profitPerKg;

  int get _effCartons => _result!.cartons;
  int get _effPallets => _result!.pallets;
  double get _effNetWeight => _result!.netWeight;
  double get _effGrossWeight => _result!.netWeight;

  Widget _buildContent(bool isNarrow) {
    final isProfit = _netProfit >= 0;
    final profitColor = isProfit ? AppTheme.success : AppTheme.danger;
    final hasItems = _result!.items.isNotEmpty;
    final hasBreakdown = _result!.breakdown.isNotEmpty;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      child: Column(children: [
        if (_result!.hasWarnings) ...[
          _buildWarningsCard(isNarrow),
          SizedBox(height: isNarrow ? 8 : 12),
        ],
        _buildShipmentInfoCard(isNarrow),
        SizedBox(height: isNarrow ? 8 : 12),
        if (!hasItems)
          _buildNoItemsWarning(),
        if (hasItems) ...[
          if (!_hideProfit) ...[
            _buildKpiCard('الإيراد',
                _revenueEgpEffective, true, AppTheme.primary,
                icon: Icons.trending_up,
                subtitle: '${_revenueFgnEffective.toStringAsFixed(2)} $_currencyCode',
                isNarrow: isNarrow),
            SizedBox(height: isNarrow ? 8 : 12),
          ],
          if (!hasBreakdown)
            _buildNoCostsNotice(),
          if (hasBreakdown) ...[
            _buildCostList(isNarrow),
            SizedBox(height: isNarrow ? 12 : 16),
          ],
          if (!_hideProfit) ...[
            _buildKpiCard(
                'إجمالي الربح', _grossProfit, true, const Color(0xFF3B82F6),
                prefix: '+', isNarrow: isNarrow),
            SizedBox(height: isNarrow ? 8 : 12),
            _buildKpiCard('صافي الربح', _netProfit, true, profitColor,
                prefix: isProfit ? '+' : '', isNarrow: isNarrow),
            SizedBox(height: isNarrow ? 8 : 12),
            _buildMarginBar(isNarrow),
            SizedBox(height: isNarrow ? 8 : 12),
          ],
          _buildCartonAnalysis(isNarrow),
          SizedBox(height: isNarrow ? 8 : 12),
          _buildKgAnalysis(isNarrow),
          SizedBox(height: isNarrow ? 8 : 12),
          if (_result!.packingOrders.isNotEmpty) ...[
            _buildProductProfitability(isNarrow),
            SizedBox(height: isNarrow ? 8 : 12),
          ],
          if (!_hideProfit) ...[
            _buildDistributionSummary(isNarrow),
            SizedBox(height: isNarrow ? 8 : 12),
            _buildAllocationBasisSelector(),
            SizedBox(height: isNarrow ? 8 : 12),
            _buildItemProfitabilityTable(),
            SizedBox(height: isNarrow ? 8 : 12),
          ],
        ],
        _buildDebugPanel(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _buildShipmentInfoCard(bool isNarrow) {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // First row: shipment no + chips
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.info.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info_outline, color: AppTheme.info, size: 16),
            ),
            UIUtils.shipmentNoText(_result!.shipmentNo,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            _chip('${_result!.items.length} صنف', AppTheme.primary),
            _chip('${_result!.breakdown.length} تكلفة', AppTheme.warning),
          ],
        ),
        const SizedBox(height: 10),
        // Info tiles row 1
        Wrap(
          spacing: isNarrow ? 4 : 8,
          runSpacing: 8,
          children: [
            _infoTile('عدد الكراتين', _effCartons.toString(), AppTheme.primary, isNarrow),
            _infoTile('عدد البالتات', '$_effPallets', AppTheme.warning, isNarrow),
            _infoTile('الوزن الصافي', '${_effNetWeight.toStringAsFixed(0)} كجم', AppTheme.success, isNarrow),
            _infoTile('الوزن الإجمالي', '${_effGrossWeight.toStringAsFixed(0)} كجم', AppTheme.info, isNarrow),
          ],
        ),
        const SizedBox(height: 8),
        // Info tiles row 2
        Wrap(
          spacing: isNarrow ? 4 : 8,
          runSpacing: 8,
          children: [
            _infoTile('العملة', _currencyCode, AppTheme.info, isNarrow),
            _infoTile('سعر الصرف', _result!.exchangeRate.toStringAsFixed(2), AppTheme.primary, isNarrow),
            _infoTile('سعر البيع', '${_result!.shipment.exportPricePerCarton.toStringAsFixed(2)} $_currencySymbol/كرتونة', AppTheme.textSecondary, isNarrow),
            _infoTile('الإيراد', '${_revenueEgpEffective.toStringAsFixed(2)} $_currencySymbol', AppTheme.success, isNarrow),
          ],
        ),
      ]),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
    );
  }

  Widget _infoTile(String label, String value, Color color, bool isNarrow) {
    final width = isNarrow ? (MediaQuery.of(context).size.width - 56) / 2 : null;
    final tile = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
        const SizedBox(height: 2),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ],
    );
    if (width != null) {
      return SizedBox(width: width, child: tile);
    }
    return Expanded(child: tile);
  }

  Widget _buildNoItemsWarning() {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.danger.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('لا توجد أصناف مرتبطة بهذه الشحنة',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
        ),
      ]),
    );
  }

  Widget _buildNoCostsNotice() {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.warning.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('لم يتم إدخال تكاليف لهذه الشحنة بعد. أضف التكاليف من صفحة تحرير الشحنة.',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
        ),
      ]),
    );
  }

  Widget _buildWarningsCard(bool isNarrow) {
    final warningsList = <String>[];
    if (_result!.fruitCostMissing) warningsList.add('تكلفة الفاكهة غير مرتبطة بالشحنة');
    if (_result!.packingCostMissing) warningsList.add('تكلفة مواد التعبئة غير مرتبطة بالشحنة');
    if (_result!.breakdownMissing) warningsList.add('تفاصيل التكاليف غير متاحة');
    if (_result!.revenueMismatch) warningsList.add('يوجد اختلاف بين الإيرادات المحسوبة والإيرادات المسجلة');
    if (warningsList.isEmpty) return const SizedBox.shrink();
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('تحذيرات الحسابات',
                  style: TextStyle(
                      color: AppTheme.danger,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
          ]),
          const SizedBox(height: 12),
          ...warningsList.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')),
                Expanded(
                  child: Text(w, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildCostList(bool isNarrow) {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text('تفصيل التكاليف',
            style: TextStyle(
                color: AppTheme.primary,
                fontSize: isNarrow ? 13 : 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        _costRow('تكلفة الفاكهة', _fruitTotal, _currencySymbol, const Color(0xFF10B981),
            _revenueEgpEffective > 0 ? _fruitTotal / _revenueEgpEffective * 100 : 0, isNarrow),
        const SizedBox(height: 6),
        _costRow('مواد التعبئة', _packingTotal, _currencySymbol, const Color(0xFF3B82F6),
            _revenueEgpEffective > 0 ? _packingTotal / _revenueEgpEffective * 100 : 0, isNarrow),
        const SizedBox(height: 6),
        _costRow('لوجستيك', _logisticsTotal, _currencySymbol, const Color(0xFFF59E0B),
            _revenueEgpEffective > 0 ? _logisticsTotal / _revenueEgpEffective * 100 : 0, isNarrow),
        const SizedBox(height: 6),
        _costRow('مصاريف إدارية', _adminTotal, _currencySymbol, const Color(0xFFEC4899),
            _revenueEgpEffective > 0 ? _adminTotal / _revenueEgpEffective * 100 : 0, isNarrow),
        const SizedBox(height: 6),
        _costRow('تكاليف أخرى', _otherTotal, _currencySymbol, Colors.grey,
            _revenueEgpEffective > 0 ? _otherTotal / _revenueEgpEffective * 100 : 0, isNarrow),
        const Divider(color: AppTheme.glassBorder),
        _costRow('إجمالي التكلفة', _totalEgp, _currencySymbol, AppTheme.textSecondary,
            _revenueEgpEffective > 0 ? _totalEgp / _revenueEgpEffective * 100 : 0,
            isNarrow, bold: true),
        if (_costItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(color: AppTheme.glassBorder),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.receipt_long, color: AppTheme.warning, size: 16),
            const SizedBox(width: 6),
            Text('التكاليف المسجلة (${_costItems.length})',
                style: const TextStyle(
                    color: AppTheme.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            const Spacer(),
            if (_journalEntries.isNotEmpty)
              _buildJournalEntriesDropdown(),
          ]),
          const SizedBox(height: 8),
          ..._costItems.map((item) => _buildCostItemRow(item, isNarrow)),
        ],
      ]),
    );
  }

  Widget _buildCostItemRow(ShipmentCostItemModel item, bool isNarrow) {
    final isPaid = item.isPaid;
    final statusColor = isPaid ? AppTheme.success : AppTheme.warning;
    final statusText = isPaid ? 'مدفوع' : 'غير مدفوع';
    final revText = (item.revisionNumber != null && item.revisionNumber! > 0)
        ? ' · تعديل #${item.revisionNumber}'
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withAlpha(25)),
      ),
      child: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
              const SizedBox(height: 2),
              Text('${item.totalPrice.toStringAsFixed(2)} $_currencySymbol · $statusText$revText',
                  style: TextStyle(color: statusColor, fontSize: 10, fontFamily: 'Cairo')),
            ],
          ),
        ),
        if (isPaid) ...[
          GestureDetector(
            onTap: () => _showEditExpenseSheet(item),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.edit_outlined, color: AppTheme.warning, size: 14),
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (isPaid && item.journalEntryId != null)
          GestureDetector(
            onTap: () => JournalEntryNavigationService.openForShipmentCostItem(
              context,
              costItemId: item.id,
              journalEntryId: item.journalEntryId,
              description: item.description,
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.info.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.book_outlined, color: AppTheme.info, size: 14),
            ),
          ),
      ]),
    );
  }

  Widget _buildJournalEntriesDropdown() {
    return PopupMenuButton<String>(
      onSelected: (entryNumber) {
        final entry = _journalEntries.firstWhere(
          (e) => e['entry_number'] == entryNumber,
          orElse: () => {},
        );
        if (entry.isNotEmpty) {
          JournalEntryNavigationService.openById(context, journalEntryId: entry['entry_number']);
        }
      },
      offset: const Offset(0, 30),
      color: const Color(0xFF0A1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.glassBorder.withAlpha(40)),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('القيود المحاسبية (${_journalEntries.length})',
              style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ),
        const PopupMenuDivider(),
        ..._journalEntries.map((je) {
          final entryNum = je['entry_number']?.toString() ?? '';
          final date = je['entry_date']?.toString() ?? '';
          final debit = (je['total_debit'] as num?)?.toDouble() ?? 0;
          final cur = je['currency']?.toString() ?? 'EGP';
          final rev = (je['revision_number'] as num?)?.toInt() ?? 0;
          final revLabel = rev > 0 ? ' — تعديل #$rev' : '';
          return PopupMenuItem<String>(
            value: entryNum,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('قيد #$entryNum$revLabel',
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
                  const SizedBox(height: 2),
                  Text('$date — ${debit.toStringAsFixed(2)} $cur',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
                ],
              ),
            ),
          );
        }),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.info.withAlpha(15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.info.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined, color: AppTheme.info, size: 13),
            const SizedBox(width: 4),
            Text('عرض القيود (${_journalEntries.length})',
                style: const TextStyle(color: AppTheme.info, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, color: AppTheme.info, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _costRow(
      String label, double value, String unit, Color color, double pct,
      bool isNarrow, {bool bold = false}) {
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Cairo',
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            ),
            if (pct > 0)
              Text('(${pct.toStringAsFixed(1)}%)',
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                      fontFamily: 'Cairo')),
          ]),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text('${value.toStringAsFixed(2)} $unit',
                style: TextStyle(
                    color: color,
                    fontSize: bold ? 14 : 13,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                    fontFamily: 'Cairo')),
          ),
        ],
      );
    }
    return Row(children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontFamily: 'Cairo',
              fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      if (pct > 0) ...[
        const SizedBox(width: 4),
        Text('(${pct.toStringAsFixed(1)}%)',
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontFamily: 'Cairo')),
      ],
      const Spacer(),
      Text('${value.toStringAsFixed(2)} $unit',
          style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontFamily: 'Cairo')),
    ]);
  }

  Widget _buildKpiCard(String label, double value, bool isEgp, Color color,
      {IconData? icon, String prefix = '', String? subtitle, bool isNarrow = false}) {
    final valueSize = isNarrow ? 14.0 : 18.0;
    return AppTheme.glassCardWidget(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 16, vertical: isNarrow ? 10 : 12),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: isNarrow ? 12 : 14,
                                fontFamily: 'Cairo')),
                        if (subtitle != null)
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 10,
                                  fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withAlpha(50)),
                  ),
                  child: Text('$prefix${value.toStringAsFixed(2)} ${isEgp ? _currencySymbol : _currencyCode}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: color,
                          fontSize: valueSize,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
              ],
            )
          : Row(children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            fontFamily: 'Cairo')),
                    if (subtitle != null)
                      Text(subtitle,
                          style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10,
                              fontFamily: 'Cairo')),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withAlpha(50)),
                ),
                child: Text('$prefix${value.toStringAsFixed(2)} ${isEgp ? _currencySymbol : _currencyCode}',
                    style: TextStyle(
                        color: color,
                        fontSize: valueSize,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ),
            ]),
    );
  }

  Widget _buildMarginBar(bool isNarrow) {
    final isProfit = _profitMargin >= 0;
    final color = isProfit ? AppTheme.success : AppTheme.danger;
    final pct = _profitMargin.abs().clamp(0, 100);

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          const Text('هامش الربح',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontFamily: 'Cairo')),
          const Spacer(),
          Text('${_profitMargin.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: color,
                  fontSize: isNarrow ? 16 : 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: Colors.white.withAlpha(10),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text('0%',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontFamily: 'Cairo')),
          const Spacer(),
          Text('100%',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontFamily: 'Cairo')),
        ]),
      ]),
    );
  }

  Widget _buildCartonAnalysis(bool isNarrow) {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text('تحليل الكرتونة',
            style: TextStyle(
                color: AppTheme.primary,
                fontSize: isNarrow ? 13 : 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        if (isNarrow) ...[
          _cartonStat('تكلفة الكرتونة', _costPerCarton, AppTheme.warning),
          const SizedBox(height: 8),
          _cartonStat('سعر البيع للكرتونة', _revPerCarton, AppTheme.primary),
          const SizedBox(height: 8),
          _cartonStat('ربح الكرتونة', _result!.profitPerCarton, AppTheme.success),
          const SizedBox(height: 8),
          _cartonStat('عدد الكراتين', _effCartons.toDouble(), AppTheme.textSecondary),
        ] else ...[
          Row(children: [
            Expanded(
              child: _cartonStat('تكلفة الكرتونة', _costPerCarton, AppTheme.warning),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cartonStat('سعر البيع للكرتونة', _revPerCarton, AppTheme.primary),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _cartonStat('ربح الكرتونة', _result!.profitPerCarton, AppTheme.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _cartonStat('عدد الكراتين', _effCartons.toDouble(), AppTheme.textSecondary),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _cartonStat(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Column(children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'Cairo')),
        const SizedBox(height: 6),
        Text(value.toStringAsFixed(2),
            style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
      ]),
    );
  }

  Widget _buildKgAnalysis(bool isNarrow) {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text('تحليل الكيلو جرام',
            style: TextStyle(
                color: AppTheme.primary,
                fontSize: isNarrow ? 13 : 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        if (isNarrow) ...[
          _cartonStat('تكلفة الكيلو', _costPerKg, AppTheme.warning),
          const SizedBox(height: 8),
          _cartonStat('سعر بيع الكيلو', _revenuePerKg, AppTheme.primary),
          const SizedBox(height: 8),
          _cartonStat('ربح الكيلو', _profitPerKg, AppTheme.success),
        ] else
          Row(children: [
            Expanded(child: _cartonStat('تكلفة الكيلو', _costPerKg, AppTheme.warning)),
            const SizedBox(width: 8),
            Expanded(child: _cartonStat('سعر بيع الكيلو', _revenuePerKg, AppTheme.primary)),
            const SizedBox(width: 8),
            Expanded(child: _cartonStat('ربح الكيلو', _profitPerKg, AppTheme.success)),
          ]),
      ]),
    );
  }

  Widget _buildDistributionSummary(bool isNarrow) {
    if (_result!.breakdown.isEmpty) return const SizedBox.shrink();
    final fgn = _result!.totalCost - _fruitTotal - _packingTotal;
    final egp = _totalEgp;
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text('توزيع التكاليف',
            style: TextStyle(
                color: AppTheme.primary,
                fontSize: isNarrow ? 13 : 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        _distRow('محلي (ج.م)', _fruitTotal + _packingTotal, egp, AppTheme.success, isNarrow),
        const SizedBox(height: 4),
        _distRow('أجنبي ($_currencyCode)', fgn * _result!.exchangeRate, egp, AppTheme.warning, isNarrow),
        const SizedBox(height: 4),
        _distRow('نسبة التكلفة للإيراد', _revenueEgpEffective > 0 ? egp / _revenueEgpEffective * 100 : 0, 100, AppTheme.info, isNarrow, unit: '%'),
      ]),
    );
  }

  Widget _distRow(String label, double value, double total, Color color, bool isNarrow, {String unit = ''}) {
    final pct = total > 0 ? value / total * 100 : 0.0;
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
        ),
        const SizedBox(width: 8),
        Text('${value.toStringAsFixed(2)}${unit.isEmpty ? ' $_currencySymbol' : unit}',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (pct / 100).clamp(0.0, 1.0),
          backgroundColor: Colors.white.withAlpha(8),
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 6,
        ),
      ),
    ]);
  }

  // ── Expense Entry from Profitability Page ─────────────────────────────────

  void _showAddExpenseSheet() {
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '1.0');

    String expenseType = 'other'; // 'shipping' | 'clearing' | 'other'
    int? selectedShippingCompanyId;
    int? selectedClearingAgentId;
    int? selectedExpenseAccountId;
    String selectedSource = 'none';
    int? selectedSourceId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.90,
            decoration: const BoxDecoration(
              color: Color(0xFF0A1628),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('إضافة مصروف جديد',
                    style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: [
                    // ── Expense Type Selector ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.glassBorder.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.glassBorder.withAlpha(30)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('نوع المصروف',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        const SizedBox(height: 8),
                        Row(children: [
                          _sourceChip('شركات الشحن', 'shipping', expenseType, (v) => setModalState(() {
                            expenseType = v;
                            selectedShippingCompanyId = null;
                            selectedClearingAgentId = null;
                            selectedExpenseAccountId = null;
                          })),
                          const SizedBox(width: 8),
                          _sourceChip('مخلص', 'clearing', expenseType, (v) => setModalState(() {
                            expenseType = v;
                            selectedShippingCompanyId = null;
                            selectedClearingAgentId = null;
                            selectedExpenseAccountId = null;
                          })),
                          const SizedBox(width: 8),
                          _sourceChip('أخرى', 'other', expenseType, (v) => setModalState(() {
                            expenseType = v;
                            selectedShippingCompanyId = null;
                            selectedClearingAgentId = null;
                            selectedExpenseAccountId = null;
                          })),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // ── Conditional Entity Fields ──
                    if (expenseType == 'shipping') ...[
                      _buildEntityDropdown('شركة الشحن', _shippingCompanies, selectedShippingCompanyId,
                          (v) => setModalState(() => selectedShippingCompanyId = v)),
                      const SizedBox(height: 12),
                    ],
                    if (expenseType == 'clearing') ...[
                      _buildEntityDropdown('المخلص', _clearingAgents, selectedClearingAgentId,
                          (v) => setModalState(() => selectedClearingAgentId = v)),
                      const SizedBox(height: 12),
                    ],
                    if (expenseType == 'other') ...[
                      _buildExpenseAccountDropdown('التصنيف (حساب المصروف)', _expenseAccounts, selectedExpenseAccountId,
                          (v) => setModalState(() => selectedExpenseAccountId = v)),
                      const SizedBox(height: 12),
                    ],

                    // ── Common Fields ──
                    _buildBottomSheetTextField('البيان', descCtrl),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _buildBottomSheetTextField('الكمية', qtyCtrl, keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildBottomSheetTextField('سعر الوحدة', priceCtrl, keyboardType: TextInputType.number)),
                    ]),
                    const SizedBox(height: 12),
                    _buildBottomSheetTextField('سعر الصرف', rateCtrl, keyboardType: TextInputType.number),
                    const SizedBox(height: 16),

                    // ── Payment Source ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.glassBorder.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.glassBorder.withAlpha(30)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('مصدر الدفع',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        const SizedBox(height: 8),
                        Row(children: [
                          _sourceChip('بدون سداد', 'none', selectedSource, (v) => setModalState(() { selectedSource = v; selectedSourceId = null; })),
                          const SizedBox(width: 8),
                          _sourceChip('خزينة', 'treasury', selectedSource, (v) => setModalState(() => selectedSource = v)),
                          const SizedBox(width: 8),
                          _sourceChip('بنك', 'bank', selectedSource, (v) => setModalState(() => selectedSource = v)),
                        ]),
                        if (selectedSource == 'treasury') ...[
                          const SizedBox(height: 8),
                          _buildSourceDropdown('اختر الخزينة', _treasuries, selectedSourceId,
                              (v) => setModalState(() => selectedSourceId = v)),
                        ],
                        if (selectedSource == 'bank') ...[
                          const SizedBox(height: 8),
                          _buildSourceDropdown('اختر الحساب البنكي', _bankAccounts, selectedSourceId,
                              (v) => setModalState(() => selectedSourceId = v)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  border: Border(top: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : () async {
                        final desc = descCtrl.text.trim();
                        if (desc.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('أدخل البيان'), backgroundColor: AppTheme.warning),
                          );
                          return;
                        }
                        final qty = double.tryParse(qtyCtrl.text) ?? 1;
                        final price = double.tryParse(priceCtrl.text) ?? 0;
                        final rate = double.tryParse(rateCtrl.text) ?? 1.0;

                        // Validate entity selection
                        if (expenseType == 'shipping' && selectedShippingCompanyId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('اختر شركة الشحن'), backgroundColor: AppTheme.warning),
                          );
                          return;
                        }
                        if (expenseType == 'clearing' && selectedClearingAgentId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('اختر المخلص'), backgroundColor: AppTheme.warning),
                          );
                          return;
                        }
                        if (expenseType == 'other' && selectedExpenseAccountId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('اختر حساب المصروف'), backgroundColor: AppTheme.warning),
                          );
                          return;
                        }
                        if (selectedSource == 'none' || selectedSourceId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('اختر مصدر السداد'), backgroundColor: AppTheme.warning),
                          );
                          return;
                        }

                        Navigator.pop(ctx);
                        await _addExpense(
                          description: desc,
                          quantity: qty,
                          unitPrice: price,
                          exchangeRate: rate,
                          expenseAccountId: selectedExpenseAccountId,
                          shippingCompanyId: selectedShippingCompanyId,
                          clearingAgentId: selectedClearingAgentId,
                          sourceType: selectedSource,
                          sourceId: selectedSourceId!,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('إضافة وسداد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheetTextField(String label, TextEditingController ctrl,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo'),
        filled: true,
        fillColor: AppTheme.glassBorder.withAlpha(10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildExpenseAccountDropdown(String label, List<Map<String, dynamic>> accounts, int? value, ValueChanged<int?> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      dropdownColor: const Color(0xFF0A1628),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo'),
        filled: true,
        fillColor: AppTheme.glassBorder.withAlpha(10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: accounts.map((a) {
        final code = a['account_code']?.toString() ?? '';
        final name = a['account_name']?.toString() ?? a['name']?.toString() ?? '';
        return DropdownMenuItem<int>(
          value: a['id'] as int,
          child: Text('$code — $name', style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildEntityDropdown(String label, List<Map<String, dynamic>> entities, int? value, ValueChanged<int?> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      dropdownColor: const Color(0xFF0A1628),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo'),
        filled: true,
        fillColor: AppTheme.glassBorder.withAlpha(10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: entities.map((e) {
        final name = e['name']?.toString() ?? '';
        return DropdownMenuItem<int>(
          value: e['id'] as int,
          child: Text(name, style: const TextStyle(fontSize: 12, fontFamily: 'Cairo')),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _sourceChip(String label, String value, String selected, ValueChanged<String> onTap) {
    final isActive = value == selected;
    final color = isActive ? AppTheme.success : AppTheme.textMuted;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(isActive ? 25 : 10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildSourceDropdown(String label, List<Map<String, dynamic>> items, int? value, ValueChanged<int?> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      dropdownColor: const Color(0xFF0A1628),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo'),
        filled: true,
        fillColor: AppTheme.glassBorder.withAlpha(10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items.map((t) {
        final name = t['name']?.toString() ?? '';
        final bal = (t['balance'] as num?)?.toDouble() ?? 0;
        return DropdownMenuItem<int>(
          value: t['id'] as int,
          child: Text('$name (${bal.toStringAsFixed(2)})', style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Future<void> _addExpense({
    required String description,
    required double quantity,
    required double unitPrice,
    required double exchangeRate,
    int? expenseAccountId,
    int? shippingCompanyId,
    int? clearingAgentId,
    required String sourceType,
    required int sourceId,
  }) async {
    setState(() => _saving = true);
    try {
      final result = await Supabase.instance.client.rpc(
        'rpc_save_profitability_expense',
        params: {
          'p_shipment_id': widget.shipmentId,
          'p_category': 'other',
          'p_report_category_id': null,
          'p_description': description,
          'p_quantity': quantity,
          'p_unit_price': unitPrice,
          'p_exchange_rate': exchangeRate,
          'p_original_currency': 'EGP',
          'p_supplier_id': null,
          'p_supplier_currency': null,
          'p_source_type': sourceType,
          'p_source_id': sourceId,
          if (expenseAccountId != null) 'p_expense_account_id': expenseAccountId,
          if (shippingCompanyId != null) 'p_shipping_company_id': shippingCompanyId,
          if (clearingAgentId != null) 'p_clearing_agent_id': clearingAgentId,
        },
      );

      if (result is Map && result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إضافة المصروف وتسجيل القيد المحاسبي بنجاح'),
              backgroundColor: AppTheme.success,
            ),
          );
          await _load(); // Refresh all data
        }
      } else {
        final error = result is Map ? result['error'] ?? 'فشل إضافة المصروف' : 'فشل إضافة المصروف';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString()), backgroundColor: AppTheme.danger),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Edit Expense from Profitability Page ──────────────────────────────────

  void _showEditExpenseSheet(ShipmentCostItemModel item) {
    final descCtrl = TextEditingController(text: item.description);
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final priceCtrl = TextEditingController(text: item.unitPrice.toString());

    String selectedSource = item.paymentSourceType ?? 'treasury';
    int? selectedSourceId = item.paymentSourceId;
    int? selectedExpenseAccountId = item.expenseAccountId;

    // Determine expense type from existing data
    String expenseType = 'other';
    int? selectedShippingCompanyId = item.shippingCompanyId;
    int? selectedClearingAgentId = item.clearingAgentId;

    if (selectedShippingCompanyId != null) {
      expenseType = 'shipping';
    } else if (selectedClearingAgentId != null) {
      expenseType = 'clearing';
    } else {
      expenseType = 'other';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFF0A1628),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.edit_outlined, color: AppTheme.warning, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('تعديل المصروف',
                        style: TextStyle(color: AppTheme.warning, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  ),
                  if (item.revisionNumber != null && item.revisionNumber! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('تعديل #${item.revisionNumber}',
                          style: const TextStyle(color: AppTheme.warning, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: [
                    // Warning about reversal
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withAlpha(10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.warning.withAlpha(30)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline, color: AppTheme.warning, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('سيتم عكس القيد القديم وإنشاء قيد جديد بالقيمة المحدثة',
                              style: const TextStyle(color: AppTheme.warning, fontSize: 10, fontFamily: 'Cairo')),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // ── Expense Type Selector ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.glassBorder.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.glassBorder.withAlpha(30)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('نوع المصروف',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        const SizedBox(height: 8),
                        Row(children: [
                          _sourceChip('شركات الشحن', 'shipping', expenseType, (v) => setModalState(() {
                            expenseType = v;
                            selectedShippingCompanyId = null;
                            selectedClearingAgentId = null;
                            selectedExpenseAccountId = null;
                          })),
                          const SizedBox(width: 8),
                          _sourceChip('مخلص', 'clearing', expenseType, (v) => setModalState(() {
                            expenseType = v;
                            selectedShippingCompanyId = null;
                            selectedClearingAgentId = null;
                            selectedExpenseAccountId = null;
                          })),
                          const SizedBox(width: 8),
                          _sourceChip('أخرى', 'other', expenseType, (v) => setModalState(() {
                            expenseType = v;
                            selectedShippingCompanyId = null;
                            selectedClearingAgentId = null;
                            selectedExpenseAccountId = null;
                          })),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // ── Conditional Entity Fields ──
                    if (expenseType == 'shipping') ...[
                      _buildEntityDropdown('شركة الشحن', _shippingCompanies, selectedShippingCompanyId,
                          (v) => setModalState(() => selectedShippingCompanyId = v)),
                      const SizedBox(height: 12),
                    ],
                    if (expenseType == 'clearing') ...[
                      _buildEntityDropdown('المخلص', _clearingAgents, selectedClearingAgentId,
                          (v) => setModalState(() => selectedClearingAgentId = v)),
                      const SizedBox(height: 12),
                    ],
                    if (expenseType == 'other') ...[
                      _buildExpenseAccountDropdown('التصنيف (حساب المصروف)', _expenseAccounts, selectedExpenseAccountId,
                          (v) => setModalState(() => selectedExpenseAccountId = v)),
                      const SizedBox(height: 12),
                    ],

                    _buildBottomSheetTextField('البيان', descCtrl),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _buildBottomSheetTextField('الكمية', qtyCtrl, keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildBottomSheetTextField('سعر الوحدة', priceCtrl, keyboardType: TextInputType.number)),
                    ]),
                    const SizedBox(height: 16),
                    // Payment source
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.glassBorder.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.glassBorder.withAlpha(30)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('وسيلة السداد',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        const SizedBox(height: 8),
                        Row(children: [
                          _sourceChip('خزينة', 'treasury', selectedSource, (v) => setModalState(() => selectedSource = v)),
                          const SizedBox(width: 8),
                          _sourceChip('بنك', 'bank', selectedSource, (v) => setModalState(() => selectedSource = v)),
                        ]),
                        if (selectedSource == 'treasury') ...[
                          const SizedBox(height: 8),
                          _buildSourceDropdown('اختر الخزينة', _treasuries, selectedSourceId,
                              (v) => setModalState(() => selectedSourceId = v)),
                        ],
                        if (selectedSource == 'bank') ...[
                          const SizedBox(height: 8),
                          _buildSourceDropdown('اختر الحساب البنكي', _bankAccounts, selectedSourceId,
                              (v) => setModalState(() => selectedSourceId = v)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  border: Border(top: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : () async {
                        final desc = descCtrl.text.trim();
                        if (desc.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('أدخل البيان'), backgroundColor: AppTheme.warning),
                          );
                          return;
                        }
                        final qty = double.tryParse(qtyCtrl.text) ?? 1;
                        final price = double.tryParse(priceCtrl.text) ?? 0;

                        if (selectedSourceId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('اختر مصدر السداد'), backgroundColor: AppTheme.warning),
                          );
                          return;
                        }

                        Navigator.pop(ctx);
                        await _editExpense(
                          item: item,
                          description: desc,
                          quantity: qty,
                          unitPrice: price,
                          sourceType: selectedSource,
                          sourceId: selectedSourceId!,
                          expenseAccountId: selectedExpenseAccountId,
                          shippingCompanyId: selectedShippingCompanyId,
                          clearingAgentId: selectedClearingAgentId,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.warning,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('حفظ التعديل', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _editExpense({
    required ShipmentCostItemModel item,
    required String description,
    required double quantity,
    required double unitPrice,
    required String sourceType,
    required int sourceId,
    int? expenseAccountId,
    int? shippingCompanyId,
    int? clearingAgentId,
  }) async {
    setState(() => _saving = true);
    try {
      final result = await _costItemDao.editExpense(
        costItemId: item.id!,
        description: description,
        quantity: quantity,
        unitPrice: unitPrice,
        sourceType: sourceType,
        sourceId: sourceId,
        expenseAccountId: expenseAccountId,
        shippingCompanyId: shippingCompanyId,
        clearingAgentId: clearingAgentId,
      );

      if (result.containsKey('success') && result['success'] == true) {
        if (mounted) {
          final oldAmt = result['old_amount'] ?? 0;
          final newAmt = result['new_amount'] ?? 0;
          final rev = result['revision'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تعديل المصروف (تعديل #$rev): $oldAmt → $newAmt $_currencySymbol'),
              backgroundColor: AppTheme.success,
            ),
          );
          await _load();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildDebugPanel() {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.bug_report, color: AppTheme.textMuted, size: 14),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('معلومات التصحيح',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.refresh, color: AppTheme.primary, size: 14),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _debugRow('shipment_id', '${_result!.shipment.id}'),
        _debugRow('shipment_no', _result!.shipment.shipmentNo),
        _debugRow('status', _result!.shipment.status),
        _debugRow('items_count', '${_result!.items.length}'),
        _debugRow('total_cartons', '${_result!.cartons}'),
        _debugRow('total_pallets', '${_result!.pallets}'),
        _debugRow('total_net_weight', _result!.netWeight.toStringAsFixed(2)),
        _debugRow('total_gross_weight', _result!.netWeight.toStringAsFixed(2)),
        _debugRow('revenue_from_items', '${_result!.revenueEgp.toStringAsFixed(2)} $_currencySymbol'),
        _debugRow('revenue_from_shipment', '${_result!.revenueEgp.toStringAsFixed(2)} $_currencySymbol'),
        _debugRow('active_source', _result!.revenueEur > 0 ? 'items' : 'shipment'),
        _debugRow('exchange_rate', _result!.exchangeRate.toStringAsFixed(4)),
        _debugRow('currency', _currencyCode),
        _debugRow('cost_breakdown_rows', '${_result!.breakdown.length}'),
        _debugRow('packing_orders', '${_result!.packingOrders.length}'),
        if (_error != null)
          _debugRow('error', _error!, color: AppTheme.danger),
      ]),
    );
  }

  Widget _debugRow(String label, String value, {Color color = AppTheme.textMuted}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text('$label: ',
            style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
        Expanded(
          child: Directionality(textDirection: TextDirection.ltr, child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo'))),
        ),
      ]),
    );
  }

  Widget _buildProductProfitability(bool isNarrow) {
    if (_result!.packingOrders.isEmpty) return const SizedBox.shrink();

    final Map<int, Map<String, dynamic>> products = {};
    for (final po in _result!.packingOrders) {
      if (po.fruitTypeId == null) continue;
      products.putIfAbsent(po.fruitTypeId!, () => {
        'productId': po.fruitTypeId,
        'productName': po.productName ?? 'منتج ${po.fruitTypeId}',
        'cartons': 0,
        'weight': 0.0,
        'allocatedCost': 0.0,
      });
      products[po.fruitTypeId!]!['cartons'] = (products[po.fruitTypeId!]!['cartons'] as int) + po.cartonCount;
      products[po.fruitTypeId!]!['weight'] = (products[po.fruitTypeId!]!['weight'] as double) + po.totalNetWeight;
    }

    for (final a in _allocations) {
      if (products.containsKey(a.finishedProductId)) {
        products[a.finishedProductId]!['allocatedCost'] = (products[a.finishedProductId]!['allocatedCost'] as double) + a.allocatedAmount;
      }
    }

    final er = _result!.shipment.exchangeRate;
    final fruitTotal = _fruitTotal;
    final packingTotal = _packingTotal;
    final totalCartons = _effCartons;
    final avgPrice = _revenueEgpEffective / (totalCartons > 0 ? totalCartons : 1);

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ربحية كل منتج',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: isNarrow ? 13 : 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          ...products.entries.map((e) {
            final p = e.value;
            final prodCartons = (p['cartons'] as int);
            final prodWeight = (p['weight'] as double);
            final allocatedCost = (p['allocatedCost'] as double) * er;
            final fruitShare = totalCartons > 0 ? fruitTotal * (prodCartons / totalCartons) : 0.0;
            final packingShare = totalCartons > 0 ? packingTotal * (prodCartons / totalCartons) : 0.0;
            final totalProdCost = allocatedCost + fruitShare + packingShare;
            final prodRevenue = prodCartons * avgPrice;
            final prodProfit = prodRevenue - totalProdCost;
            final prodMargin = prodRevenue > 0 ? prodProfit / prodRevenue * 100 : 0.0;
            final profitColor = prodProfit >= 0 ? AppTheme.success : AppTheme.danger;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: profitColor.withAlpha(8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: profitColor.withAlpha(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: profitColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p['productName'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: profitColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${prodMargin.toStringAsFixed(1)}%',
                          style: TextStyle(color: profitColor, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  if (isNarrow)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _prodStat('كراتين', prodCartons.toString(), AppTheme.textSecondary),
                        _prodStat('وزن', '${prodWeight.toStringAsFixed(0)} كجم', AppTheme.textSecondary),
                        _prodStat('تكلفة', '${totalProdCost.toStringAsFixed(2)} $_currencySymbol', AppTheme.warning),
                        _prodStat('إيراد', '${prodRevenue.toStringAsFixed(2)} $_currencySymbol', AppTheme.primary),
                        _prodStat('ربح', '${prodProfit.toStringAsFixed(2)} $_currencySymbol', profitColor),
                      ],
                    )
                  else
                    Row(children: [
                      _prodStat('كراتين', prodCartons.toString(), AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      _prodStat('وزن', '${prodWeight.toStringAsFixed(0)} كجم', AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      _prodStat('تكلفة', '${totalProdCost.toStringAsFixed(2)} $_currencySymbol', AppTheme.warning),
                      const SizedBox(width: 8),
                      _prodStat('إيراد', '${prodRevenue.toStringAsFixed(2)} $_currencySymbol', AppTheme.primary),
                      const SizedBox(width: 8),
                      _prodStat('ربح', '${prodProfit.toStringAsFixed(2)} $_currencySymbol', profitColor),
                    ]),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _prodStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontFamily: 'Cairo')),
        const SizedBox(height: 2),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildAllocationBasisSelector() {
    final labels = <String, String>{
      'cartons': 'توزيع حسب الكراتين',
      'weight': 'توزيع حسب الوزن',
      'value': 'توزيع حسب القيمة',
    };
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        const Icon(Icons.account_tree_outlined, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        const Text('أساس التوزيع:',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _allocationBasis,
              dropdownColor: const Color(0xFF0A1628),
              isExpanded: true,
              items: labels.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontFamily: 'Cairo')),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _allocationBasis = v);
              },
            ),
          ),
        ),
      ]),
    );
  }

  int _itemCartons(Map<String, dynamic> item) =>
      _parseInt(item['quantity']) ?? 0;

  double _itemWeight(Map<String, dynamic> item) =>
      _parseDouble(item['net_weight']) ?? 0.0;

  double _itemRevenueFgn(Map<String, dynamic> item) =>
      _itemCartons(item) * (_parseDouble(item['export_price_per_carton']) ?? 0.0);

  double _itemRevenueEgp(Map<String, dynamic> item) =>
      _itemRevenueFgn(item) * _result!.exchangeRate;

  double _itemAllocationShare(Map<String, dynamic> item) {
    if (_result!.items.isEmpty) return 0.0;
    switch (_allocationBasis) {
      case 'weight':
        final totalWt = _result!.netWeight;
        return totalWt > 0 ? _itemWeight(item) / totalWt : 0.0;
      case 'value':
        final totalRev = _result!.revenueEur;
        return totalRev > 0 ? _itemRevenueFgn(item) / totalRev : 0.0;
      case 'cartons':
      default:
        final totalCtn = _result!.cartons;
        return totalCtn > 0 ? _itemCartons(item) / totalCtn : 0.0;
    }
  }

  double _itemAllocatedCost(Map<String, dynamic> item) =>
      _totalEgp * _itemAllocationShare(item);

  double _itemProfit(Map<String, dynamic> item) =>
      _itemRevenueEgp(item) - _itemAllocatedCost(item);

  double _itemMargin(Map<String, dynamic> item) {
    final rev = _itemRevenueEgp(item);
    return rev > 0 ? _itemProfit(item) / rev * 100 : 0.0;
  }

  Widget _buildItemProfitabilityTable() {
    if (_result!.items.isEmpty) return const SizedBox.shrink();

    for (final item in _result!.items) {
      final name = _itemName(item);
      final ctns = _itemCartons(item);
      final wt = _itemWeight(item);
      final rev = _itemRevenueEgp(item);
      final cost = _itemAllocatedCost(item);
      final profit = _itemProfit(item);
      debugPrint('PRODUCT PROFITABILITY: product=$name '
          'cartons=$ctns weight=$wt revenue=${rev.toStringAsFixed(2)} '
          'allocatedCost=${cost.toStringAsFixed(2)} profit=${profit.toStringAsFixed(2)}');
    }

    int totalCartons = 0;
    double totalWeight = 0.0;
    double totalRevenue = 0.0;
    double totalCost = 0.0;
    double totalProfit = 0.0;
    for (final item in _result!.items) {
      totalCartons += _itemCartons(item);
      totalWeight += _itemWeight(item);
      totalRevenue += _itemRevenueEgp(item);
      totalCost += _itemAllocatedCost(item);
      totalProfit += _itemProfit(item);
    }

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ربحية الأصناف',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                  AppTheme.primary.withAlpha(15)),
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('الصنف',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'Cairo'))),
                DataColumn(label: Text('الكراتين',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'Cairo'))),
                DataColumn(label: Text('الوزن الصافي',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'Cairo'))),
                DataColumn(label: Text('الإيراد',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'Cairo'))),
                DataColumn(label: Text('التكلفة',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'Cairo'))),
                DataColumn(label: Text('الربح',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'Cairo'))),
                DataColumn(label: Text('هامش الربح',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'Cairo'))),
              ],
              rows: [
                ..._result!.items.map((item) {
                  final ctns = _itemCartons(item);
                  final wt = _itemWeight(item);
                  final rev = _itemRevenueEgp(item);
                  final cost = _itemAllocatedCost(item);
                  final profit = _itemProfit(item);
                  final margin = _itemMargin(item);
                  final isProfit = profit >= 0;
                  return DataRow(cells: [
                    DataCell(Text(_itemName(item),
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'))),
                    DataCell(Text('$ctns',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
                    DataCell(Text('${wt.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
                    DataCell(Text('${rev.toStringAsFixed(2)} $_currencySymbol',
                        style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontFamily: 'Cairo'))),
                    DataCell(Text('${cost.toStringAsFixed(2)} $_currencySymbol',
                        style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontFamily: 'Cairo'))),
                    DataCell(Text('${profit.toStringAsFixed(2)} $_currencySymbol',
                        style: TextStyle(color: isProfit ? AppTheme.success : AppTheme.danger, fontSize: 12, fontFamily: 'Cairo'))),
                    DataCell(Text('${margin.toStringAsFixed(1)}%',
                        style: TextStyle(color: isProfit ? AppTheme.success : AppTheme.danger, fontSize: 12, fontFamily: 'Cairo'))),
                  ]);
                }),
                DataRow(
                  color: WidgetStateProperty.all(
                      AppTheme.primary.withAlpha(10)),
                  cells: [
                    const DataCell(Text('الإجمالي',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                    DataCell(Text('$totalCartons',
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                    DataCell(Text('${totalWeight.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                    DataCell(Text('${totalRevenue.toStringAsFixed(2)} $_currencySymbol',
                        style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                    DataCell(Text('${totalCost.toStringAsFixed(2)} $_currencySymbol',
                        style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                    DataCell(Text('${totalProfit.toStringAsFixed(2)} $_currencySymbol',
                        style: TextStyle(color: totalProfit >= 0 ? AppTheme.success : AppTheme.danger, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                    const DataCell(Text('',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontFamily: 'Cairo'))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _itemName(Map<String, dynamic> item) {
    final name = item['product_name']?.toString() ?? item['name']?.toString();
    return (name != null && name.isNotEmpty) ? name : 'صنف ${item['finished_product_id'] ?? ''}';
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
