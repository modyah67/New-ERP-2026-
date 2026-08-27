import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../data/models/lot_model.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/dao/lot_return_dao.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'package:flutter/services.dart';
import '../../core/data_change_event_bus.dart';
import 'dart:async';

class LotReturnsPage extends StatefulWidget {
  const LotReturnsPage({super.key});

  @override
  State<LotReturnsPage> createState() => _LotReturnsPageState();
}

class LotStationInfo {
  final String stationId;
  final String stationName;
  final double remainingQuantity;
  LotStationInfo(this.stationId, this.stationName, this.remainingQuantity);
}

class LotBatchInfo {
  final int batchId;
  final String stationId;
  final String stationName;
  final double remainingQuantity;
  LotBatchInfo(this.batchId, this.stationId, this.stationName, this.remainingQuantity);
}

class GroupedLotReturn {
  final LotReceiptModel originalLot;
  final List<LotStationInfo> stations;
  final List<LotBatchInfo> batches;
  double get totalRemaining => stations.fold<double>(0, (s, e) => s + e.remainingQuantity);
  GroupedLotReturn(this.originalLot, this.stations, this.batches);
}

class _LotReturnsPageState extends State<LotReturnsPage> {
  final _lotDao = LotDao();
  final _returnDao = LotReturnDao();
  final _searchController = TextEditingController();
  final _client = Supabase.instance.client;

  int _selectedTab = 0; // 0: Available for return, 1: Return history & GL
  List<GroupedLotReturn> _lots = [];
  List<GroupedLotReturn> _filteredLots = [];
  List<Map<String, dynamic>> _historyReturns = [];
  List<Map<String, dynamic>> _filteredHistory = [];

  bool _loading = true;
  bool _initialLoad = true;
  String _searchQuery = '';
  late StreamSubscription _sub1;
  late StreamSubscription _sub2;
  late StreamSubscription _sub3;
  Timer? _debounceLoad;

  @override
  void initState() {
    super.initState();
    _load();
    _sub1 = DataChangeEventBus.instance.itemsStream.listen((_) => _debouncedLoad());
    _sub2 = DataChangeEventBus.instance.stationsStream.listen((_) => _debouncedLoad());
    _sub3 = DataChangeEventBus.instance.cropPurchasesStream.listen((_) => _debouncedLoad());
  }

  void _debouncedLoad() {
    _debounceLoad?.cancel();
    _debounceLoad = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounceLoad?.cancel();
    _sub1.cancel();
    _sub2.cancel();
    _sub3.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_initialLoad) setState(() => _loading = true);
    try {
      final lotFuture = _lotDao.getAll();
      final stationsFuture = _client.from('stations').select('id, name');
      final batchesFuture = _client.from('station_product_batches').select('id, product_code, product_name, remaining_quantity, station_id, source_type');
      final historyFuture = _returnDao.getHistoryWithDetails();

      final allLots = await lotFuture;
      final stationsResponse = await stationsFuture;
      final response = await batchesFuture;
      final history = await historyFuture;

      final Map<String, String> stationNames = {};
      for (final row in stationsResponse) {
        stationNames[row['id']?.toString() ?? ''] = row['name']?.toString() ?? 'محطة ${row['id']}';
      }

      final List<Map<String, dynamic>> allBatches = [];
      for (final row in response) {
        final sourceType = row['source_type']?.toString() ?? '';
        if (sourceType != 'lot_receipt' && sourceType != 'transfer' && sourceType != 'purchase') continue;
        allBatches.add({
          'id': row['id'] as int,
          'code': row['product_code']?.toString() ?? '',
          'pname': row['product_name']?.toString() ?? '',
          'qty': (row['remaining_quantity'] as num?)?.toDouble() ?? 0.0,
          'sid': row['station_id']?.toString() ?? '',
        });
      }

      final Map<String, Map<String, double>> lotStationQty = {};
      for (final b in allBatches) {
        final code = b['code'] as String;
        final sid = b['sid'] as String;
        final qty = b['qty'] as double;
        lotStationQty.putIfAbsent(code, () => {});
        lotStationQty[code]![sid] = (lotStationQty[code]![sid] ?? 0) + qty;
      }

      final Map<String, GroupedLotReturn> grouped = {};
      for (var lot in allLots) {
        if (!lot.isConfirmed) continue;
        final lotNum = lot.lotNumber;
        final stationMap = lotStationQty[lotNum];
        if (stationMap == null || stationMap.isEmpty) {
          continue;
        }

        final lotProductName = (lot.productName ?? '').toLowerCase();

        bool batchMatchesLot(Map<String, dynamic> b) {
          final pname = (b['pname'] as String).toLowerCase();
          if (pname.isEmpty) return true;
          if (pname.contains('مادة تعبئة') || pname.contains('مادة تعبئه')) return false;
          if (pname.contains(lotProductName) || lotProductName.contains(pname)) return true;
          return false;
        }

        final matchedBatches = allBatches.where((b) =>
          b['code'] == lot.lotNumber && batchMatchesLot(b)).toList();

        final Map<String, double> filteredStationQty = {};
        final List<LotBatchInfo> lotBatches = [];
        for (final b in matchedBatches) {
          final sid = b['sid'] as String;
          final qty = b['qty'] as double;
          if (qty <= 0) continue;
          filteredStationQty[sid] = (filteredStationQty[sid] ?? 0) + qty;
          lotBatches.add(LotBatchInfo(
            b['id'] as int,
            sid,
            stationNames[sid] ?? 'محطة $sid',
            qty,
          ));
        }
        if (filteredStationQty.isEmpty) continue;

        final stationInfos = <LotStationInfo>[];
        for (final entry in filteredStationQty.entries) {
          if (entry.value > 0) {
            stationInfos.add(LotStationInfo(
              entry.key,
              stationNames[entry.key] ?? 'محطة ${entry.key}',
              entry.value,
            ));
          }
        }
        if (stationInfos.isNotEmpty) {
          grouped[lot.lotNumber!] = GroupedLotReturn(lot, stationInfos, lotBatches);
        }
      }

      _lots = grouped.values.toList();
      _historyReturns = history;
    } catch (e) {
      debugPrint('Error loading lots for returns: $e');
    }
    _applyFilter();
    _initialLoad = false;
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    if (!mounted) return;
    final q = _searchQuery.toLowerCase().trim();
    setState(() {
      _filteredLots = _lots.where((item) {
        final lot = item.originalLot;
        final productName = (lot.productName ?? '').toLowerCase();
        final supplierName = (lot.supplierName ?? '').toLowerCase();
        final stationNames = item.stations.map((s) => s.stationName.toLowerCase()).join(' ');
        return q.isEmpty ||
            productName.contains(q) ||
            supplierName.contains(q) ||
            lot.lotNumber.toLowerCase().contains(q) ||
            stationNames.contains(q);
      }).toList();

      _filteredHistory = _historyReturns.where((item) {
        final lotInfo = item['lot_receipts'] as Map<String, dynamic>?;
        final lotNumber = (lotInfo?['lot_number'] ?? '').toString().toLowerCase();
        final productName = (lotInfo?['product_name'] ?? '').toString().toLowerCase();
        final supplierName = ((item['suppliers'] as Map<String, dynamic>?)?['name'] ?? '').toString().toLowerCase();
        final stationName = ((item['stations'] as Map<String, dynamic>?)?['name'] ?? '').toString().toLowerCase();
        final notes = (item['notes'] ?? '').toString().toLowerCase();
        final retId = item['id']?.toString() ?? '';

        return q.isEmpty ||
            retId.contains(q) ||
            lotNumber.contains(q) ||
            productName.contains(q) ||
            supplierName.contains(q) ||
            stationName.contains(q) ||
            notes.contains(q);
      }).toList();
    });
  }

  Future<void> _showReturnDialog(GroupedLotReturn item) async {
    final lot = item.originalLot;
    final batches = item.batches;

    String? selectedStationId;
    int? selectedBatchId;
    if (batches.length == 1) {
      selectedStationId = batches.first.stationId;
      selectedBatchId = batches.first.batchId;
    }

    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final selectedBatch = selectedBatchId != null
                ? batches.firstWhere((b) => b.batchId == selectedBatchId)
                : null;
            final maxQty = selectedBatch?.remainingQuantity ?? 0.0;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF0D2137),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'مرتجع ${lot.productName}',
                        style: const TextStyle(color: AppTheme.primary, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المورد: ${lot.supplierName ?? ''}', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      const Text('اختر الدفعة:', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...batches.map((b) {
                        final isSelected = selectedBatchId == b.batchId;
                        return GestureDetector(
                          onTap: saving ? null : () {
                            setState(() {
                              selectedBatchId = b.batchId;
                              selectedStationId = b.stationId;
                              qtyCtrl.clear();
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primary.withAlpha(25)
                                  : const Color(0x1AFFFFFF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppTheme.primary : AppTheme.glassBorder.withAlpha(40),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b.stationName, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                                      const SizedBox(height: 2),
                                      Text('الدفعة #${b.batchId}', style: TextStyle(color: AppTheme.textSecondary.withAlpha(180), fontFamily: 'Cairo', fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${b.remainingQuantity.toStringAsFixed(1)} ${lot.purchaseMode == "carton" ? "كرتونة" : "كجم"}',
                                  style: TextStyle(
                                    color: isSelected ? AppTheme.warning : AppTheme.textSecondary,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (selectedBatchId != null) ...[
                        const SizedBox(height: 12),
                        Text('الكمية المتبقية: ${maxQty.toStringAsFixed(1)}', style: const TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: qtyCtrl,
                          enabled: !saving,
                          decoration: InputDecoration(
                            labelText: 'الكمية المرتجعة *',
                            hintText: 'الحد الأقصى ${maxQty.toStringAsFixed(1)}',
                            filled: true,
                            fillColor: const Color(0x1AFFFFFF),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        ),
                        const SizedBox(height: 10),
                        // TextField(
                        //   controller: notesCtrl,
                        //   enabled: !saving,
                        //   decoration: InputDecoration(
                        //     labelText: 'ملاحظات المرتجع (اختياري)',
                        //     hintText: 'سبب المرتجع...',
                        //     filled: true,
                        //     fillColor: const Color(0x1AFFFFFF),
                        //     border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        //   ),
                        //   style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        // ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                  ),
                  ElevatedButton(
                    onPressed: (saving || selectedBatchId == null) ? null : () async {
                      final val = double.tryParse(qtyCtrl.text) ?? 0;
                      if (val <= 0 || val > maxQty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('الكمية غير صحيحة'), backgroundColor: AppTheme.danger),
                        );
                        return;
                      }

                      setState(() => saving = true);
                      try {
                        final result = await _returnDao.processReturn(
                          lotId: lot.id!,
                          returnQuantity: val,
                          notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : 'مرتجع شراء محصول',
                          stationId: selectedStationId,
                          batchId: selectedBatchId,
                        );
                        if (mounted) {
                          Navigator.pop(context);
                          final jeId = result['journal_entry_id'];
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('تم تسجيل المرتجع والقيد المحاسبي بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')),
                              backgroundColor: AppTheme.success,
                              action: jeId != null ? SnackBarAction(
                                label: 'عرض القيد',
                                textColor: Colors.white,
                                onPressed: () => JournalEntryNavigationService.openForLotReturn(
                                  context,
                                  returnId: result['id'] ?? result['return_id'],
                                  journalEntryId: jeId,
                                ),
                              ) : null,
                            ),
                          );
                          _load();
                        }
                      } catch (e) {
                        setState(() => saving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: AppTheme.danger),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('تأكيد المرتجع', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
            ),
          ),
          child: Column(children: [
            _buildHeader(),
            _buildTabSelector(),
            _buildSearchBar(),
            Expanded(child: _buildBody()),
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
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16, left: 20, right: 20),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.danger.withAlpha(30), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.assignment_return_outlined, color: AppTheme.danger, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('مرتجع شراء المحاصيل',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x2205192D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder.withAlpha(40)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'المرتجعات المتاحة',
              count: _lots.length,
              isSelected: _selectedTab == 0,
              icon: Icons.inventory_2_outlined,
              onTap: () => setState(() => _selectedTab = 0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTabButton(
              title: 'سجل المرتجعات والقيود',
              count: _historyReturns.length,
              isSelected: _selectedTab == 1,
              icon: Icons.history_outlined,
              onTap: () => setState(() => _selectedTab = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required int count,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _searchController,
        onChanged: (v) {
          _searchQuery = v;
          _applyFilter();
        },
        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
        decoration: InputDecoration(
          hintText: _selectedTab == 0
              ? 'بحث باسم المحصول، المورد أو الكود...'
              : 'بحث في سجل المرتجعات باللوط، المورد، أو القيد...',
          hintStyle: TextStyle(color: AppTheme.textSecondary.withAlpha(120), fontFamily: 'Cairo', fontSize: 12),
          prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary.withAlpha(120), size: 18),
          filled: true,
          fillColor: const Color(0x3805192D),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.glassBorder.withAlpha(40))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.glassBorder.withAlpha(40))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_selectedTab == 0) {
      return _buildAvailableReturnsList();
    } else {
      return _buildHistoryReturnsList();
    }
  }

  Widget _buildAvailableReturnsList() {
    if (_filteredLots.isEmpty) {
      return const Center(
        child: Text('لا توجد محاصيل قابلة للارتجاع حالياً', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      itemCount: _filteredLots.length,
      itemBuilder: (context, index) {
        final item = _filteredLots[index];
        final lot = item.originalLot;
        final stationCount = item.stations.length;
        final unitLabel = lot.purchaseMode == 'carton' ? 'كرتونة' : 'كجم';
        return Card(
          color: const Color(0x3805192D),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.glassBorder.withAlpha(40)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showReturnDialog(item),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lot.productName ?? 'غير معروف', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                        const SizedBox(height: 4),
                        Text('المورد: ${lot.supplierName ?? 'بدون مورد'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text('رقم الشراء: ${lot.lotNumber}', style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: item.stations.map((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.info.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.info.withAlpha(40)),
                            ),
                            child: Text(
                              '${s.stationName} (${s.remainingQuantity.toStringAsFixed(0)} $unitLabel)',
                              style: const TextStyle(color: AppTheme.info, fontSize: 11, fontFamily: 'Cairo'),
                            ),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('الإجمالي المتبقي', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                      Text('${item.totalRemaining.toStringAsFixed(1)} $unitLabel', style: const TextStyle(color: AppTheme.warning, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      if (stationCount > 1) ...[
                        const SizedBox(height: 2),
                        Text('في $stationCount مخازن', style: const TextStyle(color: AppTheme.info, fontSize: 11, fontFamily: 'Cairo')),
                      ],
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _showReturnDialog(item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger.withAlpha(30),
                          foregroundColor: AppTheme.danger,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('إرجاع', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryReturnsList() {
    if (_filteredHistory.isEmpty) {
      return const Center(
        child: Text('لا توجد عمليات مرتجع مسجلة حتى الآن', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      itemCount: _filteredHistory.length,
      itemBuilder: (context, index) {
        final ret = _filteredHistory[index];
        final lotInfo = ret['lot_receipts'] as Map<String, dynamic>?;
        final supplierInfo = ret['suppliers'] as Map<String, dynamic>?;
        final stationInfo = ret['stations'] as Map<String, dynamic>?;

        final retId = ret['id']?.toString() ?? '';
        final lotNumber = lotInfo?['lot_number']?.toString() ?? '—';
        final productName = lotInfo?['product_name']?.toString() ?? 'محصول';
        final supplierName = supplierInfo?['name']?.toString() ?? '—';
        final stationName = stationInfo?['name']?.toString() ?? '—';
        final returnedQty = (ret['returned_quantity'] as num?)?.toDouble() ?? 0.0;
        final returnValue = (ret['return_value'] as num?)?.toDouble() ?? 0.0;
        final unitLabel = lotInfo?['purchase_mode'] == 'carton' ? 'كرتونة' : 'كجم';
        final dateStr = (ret['created_at'] ?? '').toString().split('T').first;
        final notes = (ret['notes'] ?? '').toString().trim();
        final jeId = ret['journal_entry_id'];

        return Card(
          color: const Color(0x3805192D),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.glassBorder.withAlpha(40)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.danger.withAlpha(60)),
                          ),
                          child: Text(
                            'مرتجع #$retId',
                            style: const TextStyle(color: AppTheme.danger, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          productName,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المورد: $supplierName', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
                          const SizedBox(height: 2),
                          Text('المحطة/المخزن: $stationName', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
                          const SizedBox(height: 2),
                          Text('رقم شراء المحصول: $lotNumber', style: const TextStyle(color: AppTheme.info, fontSize: 12, fontFamily: 'Cairo')),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('ملاحظات: $notes', style: TextStyle(color: AppTheme.textSecondary.withAlpha(180), fontSize: 12, fontFamily: 'Cairo')),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${returnedQty.toStringAsFixed(1)} $unitLabel',
                          style: const TextStyle(color: AppTheme.warning, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${returnValue.toStringAsFixed(2)} ${lotInfo?['currency'] == 'USD' ? '\$' : lotInfo?['currency'] == 'EUR' ? '€' : 'ج.م'}',
                          style: const TextStyle(color: AppTheme.danger, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // View Journal Entry Button
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => JournalEntryNavigationService.openForLotReturn(
                        context,
                        returnId: ret['id'],
                        lotNumber: lotNumber,
                        journalEntryId: jeId,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.cyan.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.cyan.withAlpha(80)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, color: AppTheme.cyan, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'عرض القيد المحاسبي',
                              style: TextStyle(
                                color: AppTheme.cyan,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (jeId != null)
                      Text(
                        'قيد رقم #$jeId',
                        style: TextStyle(color: AppTheme.textSecondary.withAlpha(160), fontSize: 11, fontFamily: 'Cairo'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
