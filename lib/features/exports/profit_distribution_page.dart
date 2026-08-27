import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/utils.dart';
import '../../core/auth_state_notifier.dart';
import '../../features/auth/auth_cubit.dart';
import '../../core/services/shipment_profitability_service.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/profit_distribution_dao.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shareholder_model.dart';
import '../../core/data_change_event_bus.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ProfitDistributionPage extends StatefulWidget {
  const ProfitDistributionPage({super.key});

  @override
  State<ProfitDistributionPage> createState() => _ProfitDistributionPageState();
}

class _ProfitDistributionPageState extends State<ProfitDistributionPage> {
  final _dao = ExportShipmentDao();
  final _settingsDao = ProfitDistributionDao();
  final _shareholderDao = ShareholderDao();

  final _profitabilityService = ShipmentProfitabilityService();
  List<ExportShipmentModel> _shipments = [];
  List<ShareholderModel> _shareholders = [];

  bool _loading = true;

  ShareholderModel? _person1;
  ShareholderModel? _person2;
  ShareholderModel? _person3;

  final Map<String, List<double>> _percentages = {};
  final Map<String, TextEditingController> _pctControllers = {};

  Map<String, String> _person4ForShipment = {};
  final Set<String> _distributedShipments = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
    });
  }

  @override
  void dispose() {
    for (final c in _pctControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsDao.saveSettings(
        person1Id: _person1?.id,
        person1Name: _person1?.name ?? 'إسلام',
        person2Id: _person2?.id,
        person2Name: _person2?.name ?? 'عبدالباطن',
        person3Id: _person3?.id,
        person3Name: _person3?.name ?? 'عماد',
        percentages: _percentages,
        person4ForShipment: _person4ForShipment,
        currencyConversions: const {},
      );
    } catch (e) {
      debugPrint('❌ Error saving distribution settings: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      _person1 = _shareholders.where((s) => s.name == 'إسلام').firstOrNull;
      _person2 = _shareholders.where((s) => s.name == 'عبدالباطن').firstOrNull;
      _person3 = _shareholders.where((s) => s.name == 'عماد').firstOrNull;

      final data = await _settingsDao.getSettings();
      if (data == null) return;

      final pctRaw = data['percentages'];
      if (pctRaw != null) {
        Map<String, dynamic> pctData = {};
        if (pctRaw is String) {
          pctData = jsonDecode(pctRaw) as Map<String, dynamic>;
        } else if (pctRaw is Map) {
          pctData = Map<String, dynamic>.from(pctRaw);
        }
        for (final entry in pctData.entries) {
          final vals = (entry.value as List).map((e) => (e as num).toDouble()).toList();
          while (vals.length < 4) {
            vals.add(0.0);
          }
          _percentages[entry.key] = vals;
        }
      }

      final p4Raw = data['person4_for_shipment'];
      if (p4Raw != null && p4Raw is Map) {
        _person4ForShipment = Map<String, String>.from(p4Raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
      }
    } catch (_) {}
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _dao.getAll(limit: 200, excludeStatus: 'cancelled'),
        _shareholderDao.getAll(limit: 200),
      ]);
      _shipments = (results[0] as List<ExportShipmentModel>)
          .where((s) => s.isConfirmed)
          .toList();
      _shareholders = results[1] as List<ShareholderModel>;

      await _loadSettings();
      await _loadDistributedStatus();

      for (final s in _shipments) {
        if (s.id != null && !_percentages.containsKey(s.id)) {
          _percentages[s.id!] = [33.33, 33.33, 33.34, 0.0];
        }
      }
      _rebuildPctControllers();
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      
      _calculateMissingProfitability();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _calculateMissingProfitability() async {
    for (int i = 0; i < _shipments.length; i++) {
      if (!mounted) break;
      final storedProfit = _shipments[i].netProfitEgp;
      if (storedProfit != 0) continue;
      try {
        final result = await _profitabilityService.calculateShipment(_shipments[i].id!.toString());
        if (mounted) {
          setState(() {
            _shipments[i] = _shipments[i].copyWith(
              netProfit: result.netProfit,
              netProfitEgp: result.netProfit,
              totalRevenueEgp: result.revenueEgp,
              totalRevenueForeign: result.revenueEur,
              totalFruitCost: result.fruitCost,
              totalPackingMaterialCost: result.packingCost,
              grossProfit: result.grossProfit,
            );
          });
        }
      } catch (_) {}
    }
  }

  void _rebuildPctControllers() {
    for (final c in _pctControllers.values) {
      c.dispose();
    }
    _pctControllers.clear();
    for (final s in _shipments) {
      final p = _percentages[s.id] ?? [0.0, 0.0, 0.0, 0.0];
      for (int i = 0; i < 3; i++) {
        final key = '${s.id}_$i';
        _pctControllers[key] = TextEditingController(
          text: p[i] > 0 ? (p[i] == p[i].roundToDouble() ? p[i].toInt().toString() : p[i].toStringAsFixed(2)) : '',
        );
      }
    }
  }

  TextEditingController _getPctController(String shipmentId, int personIndex) {
    final key = '${shipmentId}_$personIndex';
    return _pctControllers.putIfAbsent(key, () {
      final p = _percentages[shipmentId] ?? [0.0, 0.0, 0.0, 0.0];
      return TextEditingController(
        text: p[personIndex] > 0 ? (p[personIndex] == p[personIndex].roundToDouble() ? p[personIndex].toInt().toString() : p[personIndex].toStringAsFixed(2)) : '',
      );
    });
  }

  double _getPersonShare(double profit, double percentage) {
    return profit * percentage / 100.0;
  }

  double _getAutoPct4(String sid) {
    final p = _percentages[sid] ?? [0.0, 0.0, 0.0, 0.0];
    final sum3 = p[0] + p[1] + p[2];
    final auto = 100.0 - sum3;
    return auto < 0 ? 0 : auto;
  }

  double _personTotal(int index) {
    double sum = 0;
    for (final s in _shipments) {
      final sid = s.id ?? '';
      double pct;
      if (index < 3) {
        pct = (_percentages[sid] ?? [0.0, 0.0, 0.0])[index];
      } else {
        pct = _getAutoPct4(sid);
      }
      sum += _getPersonShare(s.netProfitEgp, pct);
    }
    return sum;
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
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
                ),
              ),
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                        : _buildContent(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, bottom: 12, left: 12, right: 12),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 550;
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: AppTheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.groups_outlined, color: AppTheme.primary, size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('توزيع الأرباح',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      GestureDetector(
                        onTap: _exportExcel,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.glassBorder),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.table_chart_outlined, color: AppTheme.primary, size: 14),
                              SizedBox(width: 4),
                              Text('Excel', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _loadAll,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.glassBorder),
                          ),
                          child: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 18),
                        ),
                      ),
                    ]),
                  ],
                );
              }
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppTheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.groups_outlined, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('توزيع الأرباح',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  ),
                  GestureDetector(
                    onTap: _exportExcel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.glassBorder),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.table_chart_outlined, color: AppTheme.primary, size: 20),
                          SizedBox(width: 6),
                          Text('تصدير Excel', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _loadAll,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.glassBorder),
                      ),
                      child: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 22),
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

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPersonSelectors(),
          const SizedBox(height: 16),
          _buildSummaryCards(),
          const SizedBox(height: 20),
          _buildDistributionTable(),
        ],
      ),
    );
  }

  Widget _buildPersonSelectors() {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppTheme.primary.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.person, color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('المساهمين الأساسيين (ثابتين)',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
            ],
          ),
          const Divider(color: AppTheme.glassBorder, height: 20),
          Row(
            children: [
              Expanded(child: _fixedPersonBadge('إسلام', AppTheme.primary)),
              const SizedBox(width: 10),
              Expanded(child: _fixedPersonBadge('عبدالباطن', AppTheme.accent)),
              const SizedBox(width: 10),
              Expanded(child: _fixedPersonBadge('عماد', AppTheme.warning)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fixedPersonBadge(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Center(
        child: Text(name, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final persons = [
      {'name': _person1?.name ?? 'الشخص 1', 'color': AppTheme.primary, 'index': 0},
      {'name': _person2?.name ?? 'الشخص 2', 'color': AppTheme.accent, 'index': 1},
      {'name': _person3?.name ?? 'الشخص 3', 'color': AppTheme.warning, 'index': 2},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppTheme.success.withAlpha(20), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.account_balance_wallet, color: AppTheme.success, size: 16),
            ),
            const SizedBox(width: 8),
            const Text('إجمالي الأرباح',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ],
        ),
        const SizedBox(height: 12),
        ...persons.map((p) => _personProfitCards(p['name'] as String, p['color'] as Color, p['index'] as int)),
        ..._person4GroupedCards(),
      ],
    );
  }

  List<Widget> _person4GroupedCards() {
    final Map<String, double> p4EgpTotals = {};

    for (final s in _shipments) {
      final sid = s.id ?? '';
      final p4Id = _person4ForShipment[sid];
      if (p4Id == null || p4Id.isEmpty) continue;
      final pct = _getAutoPct4(sid);
      final share = _getPersonShare(s.netProfitEgp, pct);
      p4EgpTotals[p4Id] = (p4EgpTotals[p4Id] ?? 0) + share;
    }

    if (p4EgpTotals.isEmpty) return [];

    final Set<String> allP4Ids = {...p4EgpTotals.keys};
    final colors = [AppTheme.success, AppTheme.info, const Color(0xFF8B5CF6), AppTheme.accent];
    int ci = 0;

    return allP4Ids.map((p4Id) {
      final name = _shareholders.where((sh) => sh.id == p4Id).firstOrNull?.name ?? '—';
      final egpTotal = p4EgpTotals[p4Id] ?? 0;
      final color = colors[ci % colors.length];
      ci++;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppTheme.glassCardWidget(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('الشخص 4 ($name)', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                ],
              ),
              const SizedBox(height: 10),
              _miniCardContent('مصري', 'EGP', egpTotal, AppTheme.success),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _personProfitCards(String name, Color color, int personIndex) {
    double egpTotal = 0;

    for (final s in _shipments) {
      final sid = s.id ?? '';
      final pct = (_percentages[sid] ?? [0.0, 0.0, 0.0, 0.0])[personIndex];
      final share = _getPersonShare(s.netProfitEgp, pct);
      egpTotal += share;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppTheme.glassCardWidget(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
              ],
            ),
            const SizedBox(height: 10),
            _miniCardContent('مصري', 'EGP', egpTotal, AppTheme.success),
          ],
        ),
      ),
    );
  }


  Widget _miniCardContent(String label, String currency, double amount, Color color) {
    if (amount == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface.withAlpha(80),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 9, fontFamily: 'Cairo', color: AppTheme.textSecondary.withAlpha(100))),
            const SizedBox(height: 2),
            Text('$currency 0', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: AppTheme.textSecondary.withAlpha(100))),
          ],
        ),
      );
    }
    final isNeg = amount < 0;
    final displayColor = isNeg ? AppTheme.danger : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: displayColor.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: displayColor.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontFamily: 'Cairo', color: displayColor.withAlpha(180))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text('$currency ${_fmt(amount)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: displayColor)),
          ),
        ],
      ),
    );
  }



  Widget _buildDistributionTable() {
    if (_shipments.isEmpty) {
      return const Center(
        child: Column(
          children: [
            SizedBox(height: 40),
            Icon(Icons.inbox_outlined, color: AppTheme.textSecondary, size: 48),
            SizedBox(height: 12),
            Text('لا توجد شحنات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppTheme.primary.withAlpha(20), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.table_rows, color: AppTheme.primary, size: 16),
            ),
            const SizedBox(width: 8),
            const Text('توزيع الأرباح على الشحنات',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ],
        ),
        const SizedBox(height: 12),
        ..._shipments.map((s) => _shipmentCard(s)),
      ],
    );
  }

  Widget _shipmentCard(ExportShipmentModel s) {
    final profit = s.netProfitEgp;
    final isProfit = profit >= 0;
    final profitColor = isProfit ? AppTheme.success : AppTheme.danger;
    final sid = s.id ?? '';
    final p = _percentages[sid] ?? [0.0, 0.0, 0.0, 0.0];
    final autoPct4 = _getAutoPct4(sid);
    final totalPct = p[0] + p[1] + p[2] + autoPct4;
    final isValid = (totalPct - 100).abs() < 0.01;
    final hasOverAllocated = (p[0] + p[1] + p[2]) > 100;

    final isDistributedLoc = _distributedShipments.contains(sid);
    final bool needsRedist = s.needsProfitRedistribution && isDistributedLoc;
    final cardBorder = needsRedist ? Border.all(color: AppTheme.warning, width: 2) : null;

    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      border: cardBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 400) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: UIUtils.shipmentNoText(
                          AppUtils.cleanShipmentNo(s.shipmentNo, s.id),
                          style: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: profitColor.withAlpha(20), borderRadius: BorderRadius.circular(8), border: Border.all(color: profitColor.withAlpha(50))),
                        child: Text('EGP ${_fmt(profit)}', style: TextStyle(color: profitColor, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ),
                      const SizedBox(width: 8),
                      //_viewJournalEntriesIcon(s),
                      const SizedBox(width: 8),
                      _distributeIcon(s),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
                      child: Text(_formatDate(s.shipmentDate), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Ciro')),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
                    child: Text(_formatDate(s.shipmentDate), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Ciro')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: UIUtils.shipmentNoText(
                      AppUtils.cleanShipmentNo(s.shipmentNo, s.id),
                      style: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: profitColor.withAlpha(20), borderRadius: BorderRadius.circular(8), border: Border.all(color: profitColor.withAlpha(50))),
                    child: Text(
                      'EGP ${_fmt(profit)}', style: TextStyle(color: profitColor, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo',)),
                  ),
                  const SizedBox(width: 10),
                //  _viewJournalEntriesIcon(s),
                  const SizedBox(width: 10),
                  _distributeIcon(s),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.glassBorder, height: 1),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 400) {
                return Column(
                  children: [
                    _personCard(s, 0, profit, AppTheme.primary, _person1?.name ?? 'الشخص 1'),
                    const SizedBox(height: 8),
                    _personCard(s, 1, profit, AppTheme.accent, _person2?.name ?? 'الشخص 2'),
                    const SizedBox(height: 8),
                    _personCard(s, 2, profit, AppTheme.warning, _person3?.name ?? 'الشخص 3'),
                    const SizedBox(height: 8),
                    _person4Card(s, profit),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _personCard(s, 0, profit, AppTheme.primary, _person1?.name ?? 'الشخص 1')),
                  const SizedBox(width: 8),
                  Expanded(child: _personCard(s, 1, profit, AppTheme.accent, _person2?.name ?? 'الشخص 2')),
                  const SizedBox(width: 8),
                  Expanded(child: _personCard(s, 2, profit, AppTheme.warning, _person3?.name ?? 'الشخص 3')),
                  const SizedBox(width: 8),
                  Expanded(child: _person4Card(s, profit)),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Center(
            child: hasOverAllocated
                ? const Text('تجاوز التخصيص 100%!', style: TextStyle(color: AppTheme.danger, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))
                : Text('الإجمالي: ${totalPct.toStringAsFixed(1)}%', style: TextStyle(color: isValid ? AppTheme.success : AppTheme.danger, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _personCard(ExportShipmentModel s, int personIndex, double profit, Color color, String name) {
    final sid = s.id ?? '';
    final ctrl = _getPctController(sid, personIndex);
    final share = _getPersonShare(profit, (ctrl.text.isNotEmpty ? double.tryParse(ctrl.text) ?? 0 : 0));

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(name, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: TextFormField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              onChanged: (v) {
                final val = double.tryParse(v) ?? 0;
                final pp = _percentages[sid] ?? [0.0, 0.0, 0.0, 0.0];
                _percentages[sid] = List.from(pp);
                _percentages[sid]![personIndex] = val;
                _saveSettings();
                setState(() {});
              },
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontFamily: 'Cairo'),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                suffixText: '%',
                suffixStyle: TextStyle(color: color.withAlpha(150), fontSize: 11, fontFamily: 'Cairo'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color, width: 1.5)),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('EGP ${_fmt(share)}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _person4Card(ExportShipmentModel s, double profit) {
    final sid = s.id ?? '';
    final currentP4Id = _person4ForShipment[sid];
    final autoPct4 = _getAutoPct4(sid);
    final share = _getPersonShare(profit, autoPct4);

    final p4Name = currentP4Id != null
        ? (_shareholders.where((sh) => sh.id == currentP4Id).firstOrNull?.name ?? '—')
        : '—';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.success.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(p4Name, style: const TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Text(
              autoPct4 > 0 ? '${autoPct4.toStringAsFixed(1)}%' : '—',
              style: TextStyle(
                color: autoPct4 > 0 ? AppTheme.success : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: DropdownButtonFormField<String>(
              key: ValueKey('p4_dropdown_${sid}_${currentP4Id ?? "none"}'),
              initialValue: _shareholders.any((sh) => sh.id == currentP4Id && sh.id != _person1?.id && sh.id != _person2?.id && sh.id != _person3?.id) ? currentP4Id : null,
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF0D2137),
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 11),
              decoration: InputDecoration(
                hintText: 'اختر شخص',
                hintStyle: TextStyle(color: AppTheme.textSecondary.withAlpha(120), fontFamily: 'Cairo', fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('—', style: TextStyle(fontFamily: 'Cairo', fontSize: 11))),
                ..._shareholders.where((sh) =>
                  sh.id != _person1?.id && sh.id != _person2?.id && sh.id != _person3?.id
                ).map((sh) => DropdownMenuItem<String>(
                  value: sh.id,
                  child: Text(sh.name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11), overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (id) {
                if (id == null) {
                  _person4ForShipment.remove(sid);
                } else {
                  _person4ForShipment[sid] = id;
                }
                _saveSettings();
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('EGP ${_fmt(share)}', style: const TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }



  String _fmt(double v) => v.toStringAsFixed(2);
  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _viewJournalEntriesIcon(ExportShipmentModel s) {
    return GestureDetector(
      onTap: () => _showJournalEntriesDialog(s.id?.toString() ?? '', s.shipmentNo),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.info.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.account_balance,
          color: AppTheme.info,
          size: 18,
        ),
      ),
    );
  }

  Future<void> _showJournalEntriesDialog(String shipmentId, String shipmentNo) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
    
    try {
      final entries = await _dao.getProfitDistributionJournalEntries(shipmentId);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _buildJournalEntriesDialog(entries, shipmentNo);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في جلب القيود: $e', style: const TextStyle(fontFamily: 'Cairo'))),
        );
      }
    }
  }

  void _buildJournalEntriesDialog(List<Map<String, dynamic>> entries, String shipmentNo) {
    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.background,
            title: Row(
              children: [
                const Icon(Icons.account_balance, color: AppTheme.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('قيود الأرباح - شحنة $shipmentNo', style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SizedBox(
              width: 800,
              height: 500,
              child: entries.isEmpty
                  ? const Center(child: Text('لا توجد قيود أرباح مسجلة لهذه الشحنة.', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (c, i) => const Divider(color: AppTheme.glassBorder, height: 24),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isReversal = entry['source_type'] == 'profit_distribution_reversal';
                        final color = isReversal ? AppTheme.warning : AppTheme.success;
                        final lines = List<Map<String, dynamic>>.from(entry['lines'] ?? []);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: color.withAlpha(10),
                            border: Border.all(color: color.withAlpha(50)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(entry['entry_number']?.toString() ?? '—', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                                    child: Text(isReversal ? 'قيد عكسي (تعديل)' : 'توزيع أرباح', style: TextStyle(color: color, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(entry['description']?.toString() ?? '', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                              const SizedBox(height: 4),
                              Text('تاريخ القيد: ${entry['transaction_date']?.toString().split('T').first ?? ''}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                              const SizedBox(height: 12),
                              const Row(
                                children: [
                                  Expanded(flex: 2, child: Text('الحساب', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                  Expanded(flex: 1, child: Text('مدين', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                  Expanded(flex: 1, child: Text('دائن', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                ],
                              ),
                              const Divider(color: AppTheme.glassBorder, height: 8),
                                  ...lines.map((l) {
                                final isDebit = ((l['debit'] as num?)?.toDouble() ?? 0) > 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(flex: 2, child: Text('${l['account_code']} - ${l['account_name']}', style: TextStyle(color: isDebit ? AppTheme.warning : AppTheme.success, fontSize: 12, fontFamily: 'Cairo'))),
                                      Expanded(flex: 1, child: Text(l['debit']?.toString() ?? '0', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'))),
                                      Expanded(flex: 1, child: Text(l['credit']?.toString() ?? '0', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'))),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _distributeIcon(ExportShipmentModel s) {
    final sid = s.id ?? '';
    final isDistributed = _distributedShipments.contains(sid);
    final needsRedist = s.needsProfitRedistribution && isDistributed;
    final bool canDistribute = !isDistributed || needsRedist;

    
    return GestureDetector(
      onTap: canDistribute ? () => _distributeShipment(s) : null,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: canDistribute ? AppTheme.primary.withAlpha(20) : AppTheme.success.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          canDistribute ? (needsRedist ? Icons.refresh_rounded : Icons.send_rounded) : Icons.check_circle_rounded,
          color: canDistribute ? (needsRedist ? AppTheme.warning : AppTheme.primary) : AppTheme.success,
          size: 18,
        ),
      ),
    );
  }

  Future<void> _distributeShipment(ExportShipmentModel s) async {
    final sid = s.id ?? '';
    if (sid.isEmpty) return;
    try {
      // 1. Persist the current in-memory percentages/settings to DB FIRST.
      //    This is critical: the RPC reads percentages from the DB using the
      //    shipment_id as a key. If we don't save first, the key won't exist
      //    and the RPC will silently produce zero distributions.
      await _saveSettings();

      // 2. Ensure net_profit_egp is written to the shipment row so the RPC
      //    can read it (it may only exist in-memory from profitability calc).
      if (s.netProfitEgp != 0) {
        await Supabase.instance.client
            .from('export_shipments')
            .update({'net_profit_egp': s.netProfitEgp})
            .eq('id', sid);
      }

      // 3. Call the atomic distribution RPC (handles reversal + new entries
      //    + journal posting + balance updates in a single transaction).
      await Supabase.instance.client.rpc('distribute_shipment_profit', params: {'p_shipment_id_str': sid});

      // 4. Update local UI state only AFTER confirmed DB success.
      _distributedShipments.add(sid);
      final index = _shipments.indexWhere((e) => e.id == sid);
      if (index != -1) {
        _shipments[index] = _shipments[index].copyWith(needsProfitRedistribution: false);
      }
      DataChangeEventBus.instance.notifyShareholdersChanged();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم توزيع أرباح الشحنة ${s.shipmentNo} بنجاح', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('DISTRIBUTE ERROR: $e');
      if (mounted) {
        // Extract a user-friendly message from the PostgrestException
        String errorMsg = 'تعذر توزيع الأرباح.';
        final errStr = e.toString();
        if (errStr.contains('لم يتم تعيين نسب')) {
          errorMsg = 'لم يتم تعيين نسب للمساهمين لهذه الشحنة. تأكد من حفظ نسب التوزيع أولاً.';
        } else if (errStr.contains('لا يوجد ربح')) {
          errorMsg = 'لا يوجد ربح لتوزيعه (صافي الربح = 0).';
        } else if (errStr.contains('3100')) {
          errorMsg = 'حساب الأرباح المحتجزة (3100) غير موجود في قاعدة البيانات.';
        } else if (errStr.contains('إعدادات التوزيع غير موجودة')) {
          errorMsg = 'إعدادات التوزيع غير موجودة. يرجى حفظ الإعدادات أولاً.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg, style: const TextStyle(fontFamily: 'Cairo'), maxLines: 5),
            backgroundColor: AppTheme.danger,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _loadDistributedStatus() async {
    try {
      final data = await Supabase.instance.client
          .from('shareholder_profit_distributions')
          .select('shipment_id, deleted_at')
          .isFilter('deleted_at', null);
      
      _distributedShipments.clear();
      for (final row in data as List) {
        _distributedShipments.add(row['shipment_id']?.toString() ?? '');
      }

      // Check redistribution needs for distributed shipments
      for (int i = 0; i < _shipments.length; i++) {
        final sid = _shipments[i].id;
        if (sid != null && _distributedShipments.contains(sid)) {
          final res = await Supabase.instance.client.rpc('check_profit_redistribution_needed', params: {'p_shipment_id_str': sid});
          if (res == true) {
            _shipments[i] = _shipments[i].copyWith(needsProfitRedistribution: true);
          } else {
            _shipments[i] = _shipments[i].copyWith(needsProfitRedistribution: false);
          }
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading distributed status: $e');
    }
  }


  Future<void> _exportExcel() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري التصدير...', style: TextStyle(fontFamily: 'Cairo')), duration: Duration(seconds: 2)),
    );

    final excel = Excel.createExcel();
    final sheet = excel['توزيع الأرباح'];
    excel.setDefaultSheet(sheet.sheetName);

    sheet.appendRow([
      TextCellValue('رقم الشحنة'),
      TextCellValue('التاريخ'),
      TextCellValue('صافي الربح (EGP)'),
      TextCellValue('${_person1?.name ?? ''} %'),
      TextCellValue(_person1?.name ?? ''),
      TextCellValue('${_person2?.name ?? ''} %'),
      TextCellValue(_person2?.name ?? ''),
      TextCellValue('${_person3?.name ?? ''} %'),
      TextCellValue(_person3?.name ?? ''),
      TextCellValue('الشخص 4 %'),
      TextCellValue('الشخص 4'),
    ]);

    for (final s in _shipments) {
      final profit = s.netProfitEgp;
      final sid = s.id ?? '';
      final p = _percentages[sid] ?? [0.0, 0.0, 0.0, 0.0];
      final autoPct4 = _getAutoPct4(sid);

      sheet.appendRow([
        TextCellValue(AppUtils.cleanShipmentNo(s.shipmentNo, s.id)),
        TextCellValue(_formatDate(s.shipmentDate)),
        DoubleCellValue(profit),
        DoubleCellValue(p[0]),
        TextCellValue('EGP ${_getPersonShare(profit, p[0]).toStringAsFixed(2)}'),
        DoubleCellValue(p[1]),
        TextCellValue('EGP ${_getPersonShare(profit, p[1]).toStringAsFixed(2)}'),
        DoubleCellValue(p[2]),
        TextCellValue('EGP ${_getPersonShare(profit, p[2]).toStringAsFixed(2)}'),
        DoubleCellValue(autoPct4),
        TextCellValue('EGP ${_getPersonShare(profit, autoPct4).toStringAsFixed(2)}'),
      ]);
    }

    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('الإجمالي'),
      TextCellValue(''),
      DoubleCellValue(_totalProfit()),
      TextCellValue(''),
      TextCellValue('EGP ${_personTotal(0).toStringAsFixed(2)}'),
      TextCellValue(''),
      TextCellValue('EGP ${_personTotal(1).toStringAsFixed(2)}'),
      TextCellValue(''),
      TextCellValue('EGP ${_personTotal(2).toStringAsFixed(2)}'),
      TextCellValue(''),
      TextCellValue('EGP ${_personTotal(3).toStringAsFixed(2)}'),
    ]);

    for (int i = 0; i < 11; i++) {
      sheet.setColumnWidth(i, 22);
    }

    final bytes = excel.save();
    if (bytes == null || !mounted) return;
    final dir = await FileHelper.getExportDirectory();
    final now = DateTime.now();
    final fileName = 'profit_distribution_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.xlsx';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الحفظ في: $fileName', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  double _totalProfit() {
    double sum = 0;
    for (final s in _shipments) {
      sum += s.netProfitEgp;
    }
    return sum;
  }
}
