import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/services/inventory_valuation_service.dart';

class InventoryValuationPage extends StatefulWidget {
  const InventoryValuationPage({super.key});

  @override
  State<InventoryValuationPage> createState() => _InventoryValuationPageState();
}

class _InventoryValuationPageState extends State<InventoryValuationPage> {
  static const _defaultCurrency = 'EGP';
  final _service = InventoryValuationService();
  bool _loading = true;
  List<Map<String, dynamic>> _batches = [];
  Map<String, double> _summary = {'total_qty': 0, 'total_value': 0};
  List<Map<String, dynamic>> _byProduct = [];
  List<Map<String, dynamic>> _byGrade = [];

  String _format(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}م';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)}أ';
    return v.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final batches = await _service.getBatchValuation();
      final summary = await _service.getValuationSummary();
      final byProduct = await _service.getValueByProduct();
      final byGrade = await _service.getValueByGrade();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _summary = summary;
        _byProduct = byProduct;
        _byGrade = byGrade;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
              colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        children: [
                          _buildKpiRow(),
                          const SizedBox(height: 20),
                          _buildBreakdownRow(),
                          const SizedBox(height: 20),
                          _buildDetailTable(),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 20, right: 20, bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 50))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تقييم المخزون', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('Inventory Valuation', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiRow() {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            'إجمالي الكمية',
            '${_format(_summary['total_qty'] ?? 0)} كجم',
            Icons.scale_outlined,
            AppTheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'إجمالي القيمة',
            '${_format(_summary['total_value'] ?? 0)} ${AppUtils.currencySymbol(_defaultCurrency)}',
            Icons.attach_money_outlined,
            AppTheme.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            'عدد الباتشات',
            '${_batches.length}',
            Icons.inventory_outlined,
            AppTheme.info,
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('تحليل القيمة', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildValueTable('حسب المنتج', _byProduct, 'product_name', 'total_value', 'total_qty', 'كجم')),
            const SizedBox(width: 12),
            Expanded(child: _buildValueTable('حسب الدرجة', _byGrade, 'grade', 'total_value', 'total_qty', 'كجم')),
          ],
        ),
      ],
    );
  }

  Widget _buildValueTable(String title, List<Map<String, dynamic>> items, String nameKey, String valueKey, String qtyKey, String qtyUnit) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 30)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 10),
              ...items.take(6).map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${item[nameKey]}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis),
                    ),
                    Text('${_format((item[valueKey] as num?)?.toDouble() ?? 0)} ${AppUtils.currencySymbol(_defaultCurrency)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo')),
                  ],
                ),
              )),
              if (items.isEmpty) const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا توجد بيانات', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailTable() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 30)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تفاصيل الباتشات', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 12),
              ...List.generate(_batches.length, (i) {
                final b = _batches[i];
                final value = (b['inventory_value'] as num?)?.toDouble() ?? 0;
                final qty = (b['remaining_qty'] as num?)?.toDouble() ?? 0;
                final cost = (b['purchase_cost_kg'] as num?)?.toDouble() ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    border: i < _batches.length - 1
                        ? Border(bottom: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 20)))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('${b['batch_number']}', style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo'))),
                      Expanded(flex: 2, child: Text('${b['product_name']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis)),
                      Expanded(child: Text('${b['grade']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
                      Expanded(child: Text(qty.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'))),
                      Expanded(child: Text(cost.toStringAsFixed(2), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
                      Expanded(child: Text(value.toStringAsFixed(2), style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                    ],
                  ),
                );
              }),
              if (_batches.isEmpty) const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('لا توجد باتشات نشطة', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
