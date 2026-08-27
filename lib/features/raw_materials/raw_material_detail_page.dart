import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/raw_material_dao.dart';

class RawMaterialDetailPage extends StatefulWidget {
  final String materialId;
  const RawMaterialDetailPage({super.key, required this.materialId});

  @override
  State<RawMaterialDetailPage> createState() => _RawMaterialDetailPageState();
}

class _RawMaterialDetailPageState extends State<RawMaterialDetailPage> {
  final _dao = RawMaterialDao();
  bool _loading = true;

  String _name = '';
  String _code = '';
  String _unit = '';
  String _currency = 'EGP';
  String _categoryName = '';
  double _quantity = 0;
  double _minimumStock = 3000;
  double _estimatedValue = 0;
  double _avgCost = 0;
  double _initialQuantity = 0;
  double _initialAvgPrice = 0;

  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _allBatches = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _batches = [];
    });
    try {
      final item = await _dao.getById(widget.materialId);
      final batchData = await _dao.getBatchesForMaterial(widget.materialId);

      debugPrint('📦 RawMaterialDetail _load: materialId=${widget.materialId}');
      debugPrint('   item=${item?.name} code=${item?.code}');
      debugPrint('   batches count=${(batchData['batches'] as List?)?.length ?? 0}');
      debugPrint('   batchData keys=${batchData.keys.toList()}');
      if (batchData['error'] != null) {
        debugPrint('   ⚠️ batchError: ${batchData['error']}');
      }

      if (!mounted) return;
      setState(() {
        _name = item?.name ?? '';
        _code = item?.code ?? '';
        _unit = item?.unit ?? '';
        _currency = item?.currency ?? 'EGP';
        _categoryName = item?.categoryName ?? '';
        _quantity = item?.quantity ?? 0;
        _minimumStock = item?.minimumStock ?? 3000;
        _initialQuantity = item?.initialQuantity ?? 0;
        _initialAvgPrice = item?.initialAvgPrice ?? 0;
        _estimatedValue = (batchData['totalValue'] as num?)?.toDouble() ?? 0;
        _avgCost = (batchData['avgCost'] as num?)?.toDouble() ?? 0;
        final allBatches = (batchData['batches'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _allBatches = allBatches;
        _batches = allBatches.where((b) => ((b['remaining_quantity'] as num?)?.toDouble() ?? 0) > 0).toList();
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('❌ RawMaterialDetail _load error: $e');
      debugPrint('   $st');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _unitLabel(String unit) {
    const labels = {
      'piece': 'قطعة', 'kg': 'كجم', 'box': 'كرتونة',
      'roll': 'لفة', 'bag': 'كيس', 'meter': 'متر', 'liter': 'لتر',
    };
    return labels[unit] ?? unit;
  }

  @override
  Widget build(BuildContext context) {
    final isLow = _quantity < _minimumStock && _quantity > 0;
    final isOut = _quantity == 0;
    final stockColor = isOut ? AppTheme.danger : (isLow ? AppTheme.warning : AppTheme.success);
    final stockLabel = isOut ? 'نفد' : (isLow ? 'منخفض' : 'متوفر');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildStockOverview(stockColor, stockLabel),
                    if (isLow) ...[
                      const SizedBox(height: 12),
                      _buildLowStockWarning(),
                    ],
                    const SizedBox(height: 24),
                    _buildBatchesSection(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
          ),
          child: const Icon(Icons.inventory_outlined, color: AppTheme.accent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              Row(
                children: [
                  Text(_code, style: const TextStyle(color: AppTheme.accent, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                  if (_categoryName.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_categoryName, style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontFamily: 'Cairo')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStockOverview(Color stockColor, String stockLabel) {
    final consumedQty = (_initialQuantity - _quantity).clamp(0.0, double.infinity);
    final consumedValue = consumedQty * _initialAvgPrice;
    final hasOpening = _initialQuantity > 0;

    final openingBatch = _allBatches.where((b) {
      final bn = b['batch_number']?.toString() ?? '';
      return bn.startsWith('OPENING');
    }).toList();
    final openingRemaining = openingBatch.fold<double>(0, (s, b) => s + ((b['remaining_quantity'] as num?)?.toDouble() ?? 0));
    final showOpening = hasOpening && openingRemaining > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.glassCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warehouse_outlined, color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('نظرة المخزون', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                ],
              ),

              if (showOpening) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.accent.withValues(alpha: 0.08),
                        AppTheme.accent.withValues(alpha: 0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history, size: 16, color: AppTheme.accent),
                          const SizedBox(width: 6),
                          const Text('الرصيد المبدأي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accent, fontFamily: 'Cairo')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildMiniStat('الكمية', '${openingRemaining.toStringAsFixed(0)} ${_unitLabel(_unit)}', AppTheme.accent),
                          const SizedBox(width: 16),
                           _buildMiniStat('السعر', '${AppUtils.formatNumber(_initialAvgPrice)} $_currency', AppTheme.accent),
                           const SizedBox(width: 16),
                           _buildMiniStat('القيمة', '${AppUtils.formatNumber(openingRemaining * _initialAvgPrice)} $_currency', AppTheme.accent),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStatCard('المتبقي', '${_quantity.toStringAsFixed(0)} ${_unitLabel(_unit)}', stockColor)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('القيمة التقديرية', '${AppUtils.formatNumber(_estimatedValue)} $_currency', AppTheme.primary)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildStatCard('متوسط التكلفة', '${AppUtils.formatNumber(_avgCost)} $_currency', AppTheme.accent)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('الحالة', stockLabel, stockColor)),
                ],
              ),

              if (hasOpening && consumedQty > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildStatCard('المستهلك', '${consumedQty.toStringAsFixed(0)} ${_unitLabel(_unit)}', AppTheme.danger)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard('قيمة المستهلك', '${AppUtils.formatNumber(consumedValue)} $_currency', AppTheme.danger)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontFamily: 'Cairo')),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildLowStockWarning() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'الكمية أقل من ${_minimumStock.toStringAsFixed(0)} — يجب إعادة الطلب',
              style: const TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchesSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.glassCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.local_shipping_outlined, color: AppTheme.accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('الدفعات (FIFO)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'كل دفعة بسعر وتاريخ مختلف — أول دفعة تستخدم أولاً',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.7), fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 16),
              if (_batches.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('لا توجد دفعات بعد', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: [
                      _buildBatchTableHeader(),
                      const Divider(height: 1),
                      ..._batches.asMap().entries.map((e) => _buildBatchRow(e.value, e.key)),
                      _buildBatchFooter(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatchTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0x1A00E5FF),
      child: const Row(
        children: [
          SizedBox(width: 30, child: Text('#', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 80, child: Text('التاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 100, child: Text('المخزن', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 130, child: Text('المورد / الفاتورة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 80, child: Text('الكمية المتاحة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text('سعر الصرف', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('سعر الوحدة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 100, child: Text('القيمة الإجمالية', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildBatchRow(Map<String, dynamic> batch, int index) {
    final rem = (batch['remaining_quantity'] as num?)?.toDouble() ?? 0;
    final cost = (batch['purchase_cost'] as num?)?.toDouble() ?? 0;
    final exchangeRate = (batch['exchange_rate'] as num?)?.toDouble() ?? 1.0;
    final totalRem = rem * cost;
    final date = _toLocalDate(batch['created_at']);
    final station = batch['station_name']?.toString() ?? '';
    final supplierName = batch['supplier_name']?.toString() ?? '';
    final invoiceNumber = batch['invoice_number']?.toString() ?? '';
    String sourceDesc = supplierName.isNotEmpty ? supplierName : (batch['source_type'] == 'opening' ? 'رصيد افتتاحي' : 'مشتريات');
    if (invoiceNumber.isNotEmpty) sourceDesc += ' | $invoiceNumber';
    final isEven = index % 2 == 0;

    return Container(
      color: isEven ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.04),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text('${index + 1}', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13))),
          SizedBox(width: 80, child: Text(date, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13))),
          SizedBox(width: 100, child: Text(station.isNotEmpty ? station : 'المخزن', style: const TextStyle(color: AppTheme.info, fontFamily: 'Cairo', fontSize: 13), overflow: TextOverflow.ellipsis)),
          SizedBox(width: 130, child: Text(sourceDesc, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13), overflow: TextOverflow.ellipsis)),
          SizedBox(width: 80, child: Text(rem.toStringAsFixed(0), style: TextStyle(color: rem > 0 ? AppTheme.success : AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text(exchangeRate == 1.0 ? '—' : exchangeRate.toStringAsFixed(4), style: TextStyle(color: exchangeRate == 1.0 ? AppTheme.textSecondary : AppTheme.info, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('${AppUtils.formatNumber(cost)} $_currency', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13), textAlign: TextAlign.center)),
          SizedBox(width: 100, child: Text('${AppUtils.formatNumber(totalRem)} $_currency', style: const TextStyle(color: AppTheme.accent, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildBatchFooter() {
    final totalRem = _batches.fold<double>(0, (s, b) => s + ((b['remaining_quantity'] as num?)?.toDouble() ?? 0));
    final totalRemVal = _batches.fold<double>(0, (s, b) {
      final rem = (b['remaining_quantity'] as num?)?.toDouble() ?? 0;
      final cost = (b['purchase_cost'] as num?)?.toDouble() ?? 0;
      return s + rem * cost;
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: Row(
        children: [
          const SizedBox(width: 30),
          const SizedBox(width: 80, child: Text('الإجمالي', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13))),
          const SizedBox(width: 100),
          const SizedBox(width: 130),
          SizedBox(width: 80, child: Text(totalRem.toStringAsFixed(0), style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13), textAlign: TextAlign.center)),
          const SizedBox(width: 70),
          const SizedBox(width: 80),
          SizedBox(width: 100, child: Text('${AppUtils.formatNumber(totalRemVal)} $_currency', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  String _toLocalDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.toString().substring(0, raw.toString().length >= 10 ? 10 : raw.toString().length);
    }
  }
}
