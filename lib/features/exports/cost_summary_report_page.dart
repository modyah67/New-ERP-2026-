import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/dao/cost_report_dao.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../features/auth/auth_cubit.dart';
import 'cost_details_report_page.dart';

class CostSummaryReportPage extends StatefulWidget {
  const CostSummaryReportPage({super.key});

  @override
  State<CostSummaryReportPage> createState() => _CostSummaryReportPageState();
}

class _CostSummaryReportPageState extends State<CostSummaryReportPage> {
  final _dao = CostReportDao();
  bool _loading = true;
  bool _exportLoading = false;
  List<Map<String, dynamic>> _summary = [];
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _allDetails = [];
  List<String> _customers = [];
  List<Map<String, dynamic>> _costCategories = [];

  String? _selectedCustomer;
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  String _fmtCurrency(double v) {
    return 'EGP ${NumberFormat('#,##0.00').format(v)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = _fromCtrl.text.isNotEmpty ? _fromCtrl.text : null;
      final to = _toCtrl.text.isNotEmpty ? _toCtrl.text : null;
      final results = await Future.wait([
        _dao.getSummary(
            fromDate: from, toDate: to, customer: _selectedCustomer),
        _dao.getDetails(
            fromDate: from, toDate: to, customer: _selectedCustomer),
        _dao.getDistinctCustomers(),
        Supabase.instance.client
            .from('cost_report_categories')
            .select('id, name, type')
            .order('name'),
      ]);
      if (mounted) {
        setState(() {
          _summary = (results[0] as List<Map<String, dynamic>>);
          _allDetails = results[1] as List<Map<String, dynamic>>;
          _recent = _allDetails.take(15).toList();
          _customers = results[2] as List<String>;
          _costCategories = (results[3] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
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
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: AppTheme.backgroundGradient,
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary))
                        : _buildContent(),
                  ),
                ],
              ),
              if (_exportLoading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 16),
                        Text('جاري إنشاء التقرير...',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 12,
          bottom: 12,
          left: 12,
          right: 12),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: AppTheme.glassBorder.withValues(alpha: 40))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 500;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.analytics_outlined,
                      color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('تقارير التكاليف',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                  // Text('${_summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int))} معاملة',
                  //     maxLines: 1, overflow: TextOverflow.ellipsis,
                  //     style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Cairo')),
                ]),
                // const SizedBox(height: 8),
                // Row(children: [
                //   _actionBtn(Icons.picture_as_pdf_outlined, 'PDF', _exportPdf),
                //   const SizedBox(width: 6),
                //   _actionBtn(Icons.print_outlined, 'طباعة', _printReport),
                //   const SizedBox(width: 6),
                //   _actionBtn(Icons.table_chart_outlined, 'Excel', _exportExcel),
                //   const Spacer(),
                //   GestureDetector(
                //     onTap: _load,
                //     child: Container(
                //       padding: const EdgeInsets.all(6),
                //       decoration: BoxDecoration(
                //         borderRadius: BorderRadius.circular(8),
                //         border: Border.all(color: AppTheme.glassBorder),
                //       ),
                //       child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                //     ),
                //   ),
                // ]),
              ],
            );
          }
          return Row(
            children: [
              Icon(Icons.analytics_outlined, color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('تقارير التكاليف',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ),
              // _actionBtn(Icons.picture_as_pdf_outlined, 'PDF', _exportPdf),
              // const SizedBox(width: 6),
              // _actionBtn(Icons.print_outlined, 'طباعة', _printReport),
              // const SizedBox(width: 6),
              // _actionBtn(Icons.table_chart_outlined, 'Excel', _exportExcel),
              // const SizedBox(width: 12),
              // Text('${_summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int))} معاملة',
              //     style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
              // const SizedBox(width: 12),
              // Tooltip(
              //   message: 'تحديث البيانات',
              //   child: GestureDetector(
              //     onTap: _load,
              //     child: Container(
              //       padding: const EdgeInsets.all(8),
              //       decoration: BoxDecoration(
              //         borderRadius: BorderRadius.circular(8),
              //         border: Border.all(color: AppTheme.glassBorder),
              //       ),
              //       child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              //     ),
              //   ),
              // ),
            ],
          );
        },
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: _exportLoading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.primary, size: 16),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: AppTheme.glassBorder.withValues(alpha: 15))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500) {
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _filterBtn(_fromCtrl, 'من تاريخ'),
                _filterBtn(_toCtrl, 'إلى تاريخ'),
              ],
            );
          }
          return Row(
            children: [
              _filterBtn(_fromCtrl, 'من تاريخ'),
              const SizedBox(width: 6),
              _filterBtn(_toCtrl, 'إلى تاريخ'),
            ],
          );
        },
      ),
    );
  }

  Widget _filterBtn(TextEditingController ctrl, String hint) {
    return Tooltip(
      message: 'اختيار تاريخ',
      child: GestureDetector(
        onTap: () => _pickDate(ctrl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.date_range, size: 14, color: Colors.white54),
              const SizedBox(width: 4),
              Text(ctrl.text.isEmpty ? hint : ctrl.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      color: ctrl.text.isEmpty
                          ? Colors.white54
                          : AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildContent() {
    final totalAmount =
        _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));
    final totalTx =
        _summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int));
    final highest = _summary.isNotEmpty ? _summary.first : null;
    final highestLabel =
        highest != null ? (highest['item_name'] as String) : '—';
    final lowest = _summary.length > 1 ? _summary.last : null;
    final lowestLabel = lowest != null ? (lowest['item_name'] as String) : '—';
    final lowestAmt = lowest != null ? (lowest['total_amount'] as double) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmall = width < 400;
        return SingleChildScrollView(
          padding:
              EdgeInsets.fromLTRB(isSmall ? 12 : 20, 16, isSmall ? 12 : 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKpiRow(
                  totalAmount, totalTx, highestLabel, lowestLabel, lowestAmt),
              const SizedBox(height: 20),
              _buildHighestCosts(),
              const SizedBox(height: 16),
              _buildMainCategoriesCards(totalAmount),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKpiRow(
      double total, int tx, String highest, String lowest, double lowestAmt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 400) {
          return Column(
            children: [
              Row(children: [
                Expanded(
                    child: _kpiCard('إجمالي التكاليف', 'EGP ${_fmt(total)}',
                        AppTheme.primary, Icons.monetization_on_outlined)),
                const SizedBox(width: 8),
                Expanded(
                    child: _kpiCard('عدد المعاملات', '$tx', AppTheme.info,
                        Icons.receipt_long_outlined)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _kpiCard('أعلى بند تكلفة', highest, AppTheme.warning,
                        Icons.trending_up)),
                const SizedBox(width: 8),
                Expanded(
                    child: _kpiCard(
                        'أقل بند تكلفة',
                        'EGP ${_fmt(lowestAmt)} — $lowest',
                        AppTheme.accent,
                        Icons.trending_down)),
              ]),
            ],
          );
        }
        if (width < 700) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                  width: (width - 10) / 2,
                  child: _kpiCard('إجمالي التكاليف', 'EGP ${_fmt(total)}',
                      AppTheme.primary, Icons.monetization_on_outlined)),
              SizedBox(
                  width: (width - 10) / 2,
                  child: _kpiCard('عدد المعاملات', '$tx', AppTheme.info,
                      Icons.receipt_long_outlined)),
              SizedBox(
                  width: (width - 10) / 2,
                  child: _kpiCard('أعلى بند تكلفة', highest, AppTheme.warning,
                      Icons.trending_up)),
              SizedBox(
                  width: (width - 10) / 2,
                  child: _kpiCard(
                      'أقل بند تكلفة',
                      'EGP ${_fmt(lowestAmt)} — $lowest',
                      AppTheme.accent,
                      Icons.trending_down)),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
                child: _kpiCard('إجمالي التكاليف', 'EGP ${_fmt(total)}',
                    AppTheme.primary, Icons.monetization_on_outlined)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiCard('عدد المعاملات', '$tx', AppTheme.info,
                    Icons.receipt_long_outlined)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiCard('أعلى بند تكلفة', highest, AppTheme.warning,
                    Icons.trending_up)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiCard(
                    'أقل بند تكلفة',
                    'EGP ${_fmt(lowestAmt)} — $lowest',
                    AppTheme.accent,
                    Icons.trending_down)),
          ],
        );
      },
    );
  }

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 200;
        return Container(
          padding: EdgeInsets.fromLTRB(isSmall ? 10 : 14, isSmall ? 10 : 14,
              isSmall ? 10 : 14, isSmall ? 10 : 14),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 25)),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: isSmall ? 14 : 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmall ? 10 : 11,
                            fontFamily: 'Cairo')),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: label == 'إجمالي التكاليف' ? 24 : 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                    )),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHighestCosts() {
    if (_allDetails.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: const Center(
          child: Text('لا توجد بيانات',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        ),
      );
    }

    final Map<String, Map<String, dynamic>> highest = {};
    for (final row in _allDetails) {
      final majorCat = _getMajorCategory(row);
      final amt = (row['amount'] as num?)?.toDouble() ?? 0;
      if (!highest.containsKey(majorCat) ||
          amt > ((highest[majorCat]!['amount'] as num?)?.toDouble() ?? 0)) {
        highest[majorCat] = row;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: [
                Icon(Icons.trending_up, color: AppTheme.warning, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('أعلى التكاليف (حسب البند)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...highest.entries.map((entry) {
            final catName = entry.key;
            final row = entry.value;
            final itemName = row['item_name'] as String? ?? '';
            final shipNo = row['shipment_no'] as String? ?? '';
            final amt = (row['amount'] as num?)?.toDouble() ?? 0;
            return _highestCostItem(catName, itemName, shipNo, amt);
          }),
        ],
      ),
    );
  }

  Widget _highestCostItem(
      String catName, String itemName, String shipNo, double amt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 350) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(catName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                  Text(_fmt(amt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ]),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                      'أعلى تكلفة هي $itemName ${shipNo.isNotEmpty ? 'في الشحنة رقم \u202A$shipNo\u202C' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'Cairo')),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(catName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                    const SizedBox(height: 4),
                    Text(
                        'أعلى تكلفة هي $itemName ${shipNo.isNotEmpty ? 'في الشحنة رقم \u202A$shipNo\u202C' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_fmt(amt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainCategoriesCards(double total) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    final standardOrder = [
      'تكلفة المحاصيل',
      'مواد التعبئة',
      'تعبئة وتغليف',
      'تكلفة شركات الشحن',
      'تكلفة المخلصين',
    ];

    for (final std in standardOrder) {
      grouped[std] = [];
    }

    for (final row in _allDetails) {
      final majorCat = _getMajorCategory(row);
      grouped.putIfAbsent(majorCat, () => []).add(row);
    }

    for (final cat in _costCategories) {
      final name = cat['name'] as String;
      if (name != 'محاصيل' && name != 'crop' && name != 'packing') {
        grouped.putIfAbsent(name, () => []);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 500) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تفاصيل البنود الأساسية',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  // SizedBox(
                  //   width: double.infinity,
                  //   child: ElevatedButton.icon(
                  //     onPressed: _showAddCostDialog,
                  //     icon:
                  //         const Icon(Icons.add, size: 16, color: Colors.white),
                  //     label: const Text('إضافة بند',
                  //         style: TextStyle(
                  //             fontFamily: 'Cairo',
                  //             fontSize: 12,
                  //             color: Colors.white)),
                  //     style: ElevatedButton.styleFrom(
                  //       backgroundColor: AppTheme.primary,
                  //       minimumSize: const Size(0, 36),
                  //       shape: RoundedRectangleBorder(
                  //           borderRadius: BorderRadius.circular(8)),
                  //     ),
                  //   ),
                  // ),
                ],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('تفاصيل البنود الأساسية',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                // ElevatedButton.icon(
                //   onPressed: _showAddCostDialog,
                //   icon: const Icon(Icons.add, size: 16, color: Colors.white),
                //   label: const Text('إضافة بند',
                //       style: TextStyle(
                //           fontFamily: 'Cairo',
                //           fontSize: 12,
                //           color: Colors.white)),
                //   style: ElevatedButton.styleFrom(
                //     backgroundColor: AppTheme.primary,
                //     minimumSize: const Size(0, 36),
                //     shape: RoundedRectangleBorder(
                //         borderRadius: BorderRadius.circular(8)),
                //   ),
                // ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        ...grouped.entries.map((entry) {
          final catName = entry.key;
          final rows = entry.value;
          final catTotal = rows.fold<double>(
              0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));
          final pct = total > 0 ? catTotal / total * 100 : 0.0;
          final txCount = rows.length;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CostDetailsReportPage(majorCategory: catName),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                hoverColor: Colors.white.withValues(alpha: 0.04),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.glassBorder.withValues(alpha: 40)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 350) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.category_outlined,
                                    color: AppTheme.primary, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(catName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo')),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Text('$txCount معاملة',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontFamily: 'Cairo')),
                              const Spacer(),
                              Text(_fmt(catTotal),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo')),
                              const SizedBox(width: 8),
                              Text('${pct.toStringAsFixed(1)}%',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo')),
                            ]),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.category_outlined,
                                color: AppTheme.primary, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(catName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo')),
                                const SizedBox(height: 4),
                                Text('$txCount معاملة',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_fmt(catTotal),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo')),
                              const SizedBox(height: 4),
                              Text('${pct.toStringAsFixed(1)}%',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo')),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showAddCostDialog() async {
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.cardBg,
          title: const Text('إضافة بند جديد',
              style: TextStyle(
                  color: Colors.white, fontFamily: 'Cairo', fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style:
                    const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'اسم البند',
                  labelStyle:
                      TextStyle(color: Colors.white54, fontFamily: 'Cairo'),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.primary)),
                ),
                autofocus: true,
                onSubmitted: (_) {
                  if (nameCtrl.text.trim().isNotEmpty) {
                    _addCategory(nameCtrl.text.trim(), ctx);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.white54, fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  _addCategory(nameCtrl.text.trim(), ctx);
                }
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('إضافة',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCategory(String name, BuildContext ctx) async {
    try {
      await Supabase.instance.client.from('cost_report_categories').insert({
        'name': name,
        'type': 'direct',
      });
      if (mounted) {
        Navigator.pop(ctx);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  // ── Report helpers ──

  String _generatedBy() {
    final auth = context.read<AuthCubit>().state;
    if (auth is AuthAuthenticated)
      return auth.fullName ?? auth.email ?? 'مستخدم';
    return 'مستخدم';
  }

  String _dateRangeLabel() {
    final from = _fromCtrl.text;
    final to = _toCtrl.text;
    if (from.isEmpty && to.isEmpty) return 'الكل';
    if (from.isEmpty) return 'حتى $to';
    if (to.isEmpty) return 'من $from';
    return 'من $from إلى $to';
  }

  Future<void> _exportPdf() async {
    setState(() => _exportLoading = true);
    try {
      final totalAmount =
          _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));
      final totalTx =
          _summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int));
      final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final user = _generatedBy();

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
            buildBackground: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(bgImage, fit: pw.BoxFit.cover),
            ),
          ),
          build: (ctx) => [
            _pdfHeader(font, fontBold, now, user),
            _pdfSummary(font, fontBold, totalAmount, totalTx),
            _pdfCostDistribution(font, fontBold, totalAmount),
            _pdfCostItems(font, fontBold, totalAmount),
            _pdfTransactions(font, fontBold),
          ],
        ),
      );
      await Printing.sharePdf(
          bytes: await doc.save(),
          filename: 'cost_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) _showSnack('تم تصدير PDF بنجاح');
    } catch (e) {
      if (mounted) _showSnack('فشل تصدير PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _printReport() async {
    setState(() => _exportLoading = true);
    try {
      final totalAmount =
          _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));
      final totalTx =
          _summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int));
      final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final user = _generatedBy();

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
            margin: pw.EdgeInsets.all(20),
            buildBackground: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(bgImage, fit: pw.BoxFit.cover),
            ),
          ),
          build: (ctx) => [
            _pdfHeader(font, fontBold, now, user),
            _pdfSummary(font, fontBold, totalAmount, totalTx),
            _pdfCostDistribution(font, fontBold, totalAmount),
            _pdfCostItems(font, fontBold, totalAmount),
            _pdfTransactions(font, fontBold),
          ],
        ),
      );
      await Printing.layoutPdf(onLayout: (_) => doc.save());
      if (mounted) _showSnack('تم إرسال التقرير للطباعة');
    } catch (e) {
      if (mounted) _showSnack('فشلت الطباعة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exportLoading = true);
    try {
      final excel = Excel.createExcel();
      final totalAmount =
          _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));

      // Sheet 1: Summary
      final sheet1 = excel['ملخص'];
      _excelRow(sheet1, ['بند التكلفة', 'المبلغ', 'النسبة', 'عدد المعاملات'],
          bold: true);
      for (final e in _summary) {
        final name = e['item_name'] as String;
        final amt = e['total_amount'] as double;
        final tx = e['transaction_count'] as int;
        final pct = totalAmount > 0 ? amt / totalAmount * 100 : 0.0;
        _excelRow(sheet1,
            [name, _fmtCurrency(amt), '${pct.toStringAsFixed(1)}%', '$tx']);
      }
      _excelRow(sheet1, ['الإجمالي', _fmtCurrency(totalAmount), '', '']);

      // Sheet 2: Cost Items (detailed - same as summary)
      final sheet2 = excel['بنود التكاليف'];
      _excelRow(sheet2, ['بند التكلفة', 'المبلغ', 'النسبة', 'عدد المعاملات'],
          bold: true);
      for (final e in _summary) {
        final name = e['item_name'] as String;
        final amt = e['total_amount'] as double;
        final tx = e['transaction_count'] as int;
        final pct = totalAmount > 0 ? amt / totalAmount * 100 : 0.0;
        _excelRow(sheet2,
            [name, _fmtCurrency(amt), '${pct.toStringAsFixed(1)}%', '$tx']);
      }
      _excelRow(sheet2, ['الإجمالي', _fmtCurrency(totalAmount), '', '']);

      final sheet3 = excel['المعاملات'];
      _excelRow(
          sheet3,
          [
            'التاريخ',
            'رقم الشحنة',
            'العميل',
            'بند التكلفة',
            'الكمية',
            'سعر الوحدة',
            'سعر الصرف',
            'الإجمالي بالعملة',
            'الإجمالي بالمصري',
            'البيان'
          ],
          bold: true);
      for (final r in _recent) {
        final date = r['shipment_date']?.toString() ?? '';
        final cat = r['category'] as String? ?? '';
        final amt = (r['amount'] as num?)?.toDouble() ?? 0;
        final exRate = (r['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        final actualExRate = exRate == 0 ? 1.0 : exRate;
        final totalCur = (r['total_in_currency'] as num?)?.toDouble() ?? amt;
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
        final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0;
        final currCode = r['currency']?.toString() ?? 'EGP';
        final currName = currCode.toUpperCase() == 'EGP'
            ? 'EGP'
            : currCode.toUpperCase() == 'EUR'
                ? 'EURO'
                : currCode.toUpperCase() == 'USD'
                    ? 'USD'
                    : currCode.toUpperCase() == 'GBP'
                        ? 'GBP'
                        : currCode;

        _excelRow(sheet3, [
          date.length >= 10 ? date.substring(0, 10) : date,
          r['shipment_no']?.toString() ?? '',
          r['customer_name']?.toString() ?? '',
          r['item_name']?.toString() ?? cat,
          qty.toString(),
          '$currName ${CurrencyConversionService.instance.fromBase(unitPrice, currCode, actualExRate).toStringAsFixed(2)}',
          actualExRate.toStringAsFixed(2),
          '$currName ${totalCur.toStringAsFixed(2)}',
          _fmtCurrency(amt),
          r['description']?.toString() ?? '',
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('فشل إنشاء ملف Excel');
      final fileName =
          'cost_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await Printing.sharePdf(
          bytes: Uint8List.fromList(bytes), filename: fileName);
      if (mounted) _showSnack('تم تصدير Excel بنجاح');
    } catch (e) {
      if (mounted) _showSnack('فشل تصدير Excel: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  void _excelRow(Sheet sheet, List<String> values, {bool bold = false}) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }

  // ── PDF builders ──

  pw.Widget _pdfHeader(
      pw.Font font, pw.Font fontBold, String now, String user) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(AppConstants.companyName,
            style: pw.TextStyle(
                font: fontBold, fontSize: 18, color: PdfColors.blueGrey)),
        pw.Text('تقرير التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 14, color: PdfColors.black)),
        pw.SizedBox(height: 4),
        pw.Text('تاريخ التقرير: $now',
            style: pw.TextStyle(
                font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.Text('المستخدم: $user',
            style: pw.TextStyle(
                font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.Text('نطاق التاريخ: ${_dateRangeLabel()}',
            style: pw.TextStyle(
                font: font, fontSize: 10, color: PdfColors.grey700)),
        if (_selectedCustomer != null)
          pw.Text('العميل: $_selectedCustomer',
              style: pw.TextStyle(
                  font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget _pdfSummary(pw.Font font, pw.Font fontBold, double total, int tx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ملخص التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _pdfStatCard(font, fontBold, 'الإجمالي', _fmtCurrency(total)),
            _pdfStatCard(font, fontBold, 'المعاملات', '$tx'),
            _pdfStatCard(
                font,
                fontBold,
                'أعلى بند',
                _summary.isNotEmpty
                    ? (_summary.first['item_name'] as String)
                    : '—'),
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _pdfStatCard(
      pw.Font font, pw.Font fontBold, String label, String value) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value,
              style: pw.TextStyle(
                  font: fontBold, fontSize: 12, color: PdfColors.black)),
        ],
      ),
    );
  }

  pw.Widget _pdfCostDistribution(pw.Font font, pw.Font fontBold, double total) {
    if (_summary.isEmpty || total <= 0) return pw.SizedBox();
    final barColors = [
      PdfColors.blueGrey,
      PdfColors.teal,
      PdfColors.amber,
      PdfColors.red,
      PdfColors.purple,
      PdfColors.green,
      PdfColors.orange,
      PdfColors.indigo,
      PdfColors.pink,
      PdfColors.cyan,
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('توزيع التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        ...List.generate(_summary.length, (i) {
          final e = _summary[i];
          final name = e['item_name'] as String;
          final amt = e['total_amount'] as double;
          final tx = e['transaction_count'] as int;
          final pct = amt / total * 100;
          final color = barColors[i % barColors.length];
          return pw.Container(
            margin: pw.EdgeInsets.only(bottom: 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                        width: 8,
                        height: 8,
                        decoration: pw.BoxDecoration(
                            color: color, shape: pw.BoxShape.circle)),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                        child: pw.Text(name,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9,
                                color: PdfColors.black))),
                    pw.Text(_fmtCurrency(amt),
                        style: pw.TextStyle(
                            font: font, fontSize: 9, color: PdfColors.black)),
                    pw.SizedBox(width: 8),
                    pw.SizedBox(
                        width: 40,
                        child: pw.Text('${pct.toStringAsFixed(1)}%',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9,
                                color: PdfColors.black))),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Container(
                  height: 8,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey300,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Container(
                    width: pct / 100 * 460,
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: color,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text('$tx معاملة',
                    style: pw.TextStyle(
                        font: font, fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          );
        }),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('الإجمالي:',
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
            pw.Text(_fmtCurrency(total),
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _pdfCostItems(pw.Font font, pw.Font fontBold, double total) {
    final headers = ['بند التكلفة', 'المبلغ', 'النسبة', 'المعاملات'];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('بنود التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerAlignment: pw.Alignment.center,
          cellAlignment: pw.Alignment.centerRight,
          headerStyle: pw.TextStyle(
              font: fontBold, fontSize: 10, color: PdfColors.white),
          cellStyle:
              pw.TextStyle(font: font, fontSize: 9, color: PdfColors.black),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
          cellDecoration: (row, col, isHeader) => pw.BoxDecoration(
              border:
                  pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
          headers: headers,
          data: _summary.map((e) {
            final name = e['item_name'] as String;
            final amt = e['total_amount'] as double;
            final tx = e['transaction_count'] as int;
            final pct = total > 0 ? amt / total * 100 : 0.0;
            return [
              name,
              _fmtCurrency(amt),
              '${pct.toStringAsFixed(1)}%',
              '$tx'
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('الإجمالي:',
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
            pw.Text(_fmtCurrency(total),
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _pdfTransactions(pw.Font font, pw.Font fontBold) {
    final headers = [
      'التاريخ',
      'رقم الشحنة',
      'العميل',
      'بند التكلفة',
      'المبلغ',
      'البيان'
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('المعاملات',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        if (_recent.isEmpty)
          pw.Text('لا توجد معاملات',
              style: pw.TextStyle(
                  font: font, fontSize: 10, color: PdfColors.grey700))
        else
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(
                font: fontBold, fontSize: 9, color: PdfColors.white),
            cellStyle:
                pw.TextStyle(font: font, fontSize: 8, color: PdfColors.black),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
            cellDecoration: (row, col, isHeader) => pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
            headers: headers,
            data: _recent.map((r) {
              final date = r['shipment_date']?.toString() ?? '';
              final cat = r['category'] as String? ?? '';
              final amt = (r['amount'] as num?)?.toDouble() ?? 0;
              return [
                date.length >= 10 ? date.substring(0, 10) : date,
                r['shipment_no']?.toString() ?? '',
                r['customer_name']?.toString() ?? '',
                r['item_name']?.toString() ?? cat,
                _fmtCurrency(amt),
                r['description']?.toString() ?? '',
              ];
            }).toList(),
          ),
      ],
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);
}

class _TxCell extends StatelessWidget {
  final String text;
  final bool bold;
  final bool accent;
  final bool muted;
  final TextAlign align;
  const _TxCell(this.text,
      {this.bold = false,
      this.accent = false,
      this.muted = false,
      this.align = TextAlign.start});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: accent
              ? AppTheme.primary
              : muted
                  ? Colors.white54
                  : Colors.white,
        ));
  }
}
