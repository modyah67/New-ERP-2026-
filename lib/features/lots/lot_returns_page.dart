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
import 'crop_return_pdf_service.dart';
import '../../data/models/cost_center.dart';
import '../../data/services/product_cost_center_sync_service.dart';

/// Alias for Crop Returns page
typedef CropReturnsPage = LotReturnsPage;

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
  final double purchasedQuantity;
  final double netQuantity;
  final double alreadyReturnedQuantity;
  final double availableQuantity;
  final String unitLabel;

  double get totalRemaining => availableQuantity;

  GroupedLotReturn({
    required this.originalLot,
    required this.stations,
    required this.batches,
    required this.purchasedQuantity,
    required this.netQuantity,
    required this.alreadyReturnedQuantity,
    required this.availableQuantity,
    required this.unitLabel,
  });
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

  String _formatQty(num qty, String unitLabel) {
    if (qty % 1 == 0 || unitLabel == 'كرتونة') {
      return '${qty.toInt()} $unitLabel';
    }
    return '${qty.toStringAsFixed(1)} $unitLabel';
  }

  Future<void> _load() async {
    if (_initialLoad) setState(() => _loading = true);
    try {
      final availLotsFuture = _returnDao.getAvailableLotsForReturn();
      final lotFuture = _lotDao.getAll();
      final stationsFuture = _client.from('stations').select('id, name');
      final batchesFuture = _client.from('station_product_batches').select('id, product_code, product_name, remaining_quantity, station_id, source_type, item_type, fruit_type_id, raw_material_id');
      final historyFuture = _returnDao.getHistoryWithDetails();

      final availLotsData = await availLotsFuture;
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
        final itemType = row['item_type']?.toString() ?? '';
        final rawMatId = row['raw_material_id'];

        // Only allow crop/fruit batches (lot_receipt, crop_purchase, or fruit transfer)
        if (sourceType != 'lot_receipt' && sourceType != 'crop_purchase' && sourceType != 'transfer') continue;
        if (itemType == 'material' || rawMatId != null) continue;

        allBatches.add({
          'id': row['id'] as int,
          'code': row['product_code']?.toString() ?? '',
          'pname': row['product_name']?.toString() ?? '',
          'qty': (row['remaining_quantity'] as num?)?.toDouble() ?? 0.0,
          'sid': row['station_id']?.toString() ?? '',
          'fruit_type_id': row['fruit_type_id']?.toString(),
          'item_type': itemType,
        });
      }

      final Map<String, LotReceiptModel> lotsById = {};
      final Map<String, LotReceiptModel> lotsByNumber = {};
      for (final lot in allLots) {
        if (lot.id != null) lotsById[lot.id!] = lot;
        lotsByNumber[lot.lotNumber] = lot;
      }

      final List<GroupedLotReturn> returnList = [];

      for (final avail in availLotsData) {
        final lotId = avail['lot_id']?.toString() ?? '';
        final lotNum = avail['lot_number']?.toString() ?? '';
        LotReceiptModel? lot = lotsById[lotId] ?? lotsByNumber[lotNum];
        final netQty = (avail['net_quantity'] as num?)?.toDouble() ??
            lot?.netWarehouseQuantity ??
            (avail['purchased_quantity'] as num?)?.toDouble() ?? 0.0;
        final purchasedQty = (avail['purchased_quantity'] as num?)?.toDouble() ??
            lot?.grossPurchaseQuantity ?? netQty;
        final returnedQty = (avail['already_returned_quantity'] as num?)?.toDouble() ?? 0.0;
        final availableQty = (avail['available_quantity'] as num?)?.toDouble() ?? (netQty - returnedQty);
        final unitLabel = avail['unit_label']?.toString() ?? (avail['purchase_mode'] == 'carton' ? 'كرتونة' : 'كجم');

        if (availableQty <= 0) continue;

        lot ??= LotReceiptModel(
          id: lotId,
          lotNumber: lotNum,
          fruitTypeId: avail['fruit_type_id']?.toString(),
          productName: avail['product_name']?.toString(),
          supplierId: avail['supplier_id']?.toString(),
          supplierName: avail['supplier_name']?.toString(),
          receiptDate: avail['receipt_date'] != null ? DateTime.parse(avail['receipt_date'].toString()) : DateTime.now(),
          stationId: avail['station_id']?.toString(),
          purchaseMode: avail['purchase_mode']?.toString() ?? 'weight',
          currency: avail['currency']?.toString() ?? 'EGP',
          exchangeRate: (avail['exchange_rate'] as num?)?.toDouble() ?? 1.0,
          isConfirmed: true,
        );

        final lProdName = (lot.productName ?? '').trim();
        final lFruitId = lot.fruitTypeId?.toString();

        final matchedBatches = allBatches.where((b) {
          final bCode = b['code'] as String;
          final bName = (b['pname'] as String).trim();
          final codeMatch = (bCode == lotNum || bCode == lotId);
          if (!codeMatch) return false;

          if (lProdName.isNotEmpty && bName.isNotEmpty) {
            if (bName != lProdName && !bName.contains(lProdName) && !lProdName.contains(bName)) {
              return false;
            }
          }

          final bFruitId = b['fruit_type_id']?.toString();
          if (bFruitId != null && lFruitId != null && bFruitId != lFruitId) {
            return false;
          }

          return true;
        }).toList();
        final List<LotBatchInfo> lotBatches = [];
        final Map<String, double> stationQtyMap = {};

        for (final b in matchedBatches) {
          final sid = b['sid'] as String;
          final qty = b['qty'] as double;
          if (qty > 0) {
            stationQtyMap[sid] = (stationQtyMap[sid] ?? 0) + qty;
            lotBatches.add(LotBatchInfo(
              b['id'] as int,
              sid,
              stationNames[sid] ?? 'محطة $sid',
              qty,
            ));
          }
        }

        final stationInfos = <LotStationInfo>[];
        for (final entry in stationQtyMap.entries) {
          stationInfos.add(LotStationInfo(
            entry.key,
            stationNames[entry.key] ?? 'محطة ${entry.key}',
            entry.value,
          ));
        }

        if (stationInfos.isEmpty) {
          final stId = lot.stationId ?? '1';
          stationInfos.add(LotStationInfo(
            stId,
            stationNames[stId] ?? 'المحطة الرئيسية',
            availableQty,
          ));
        }

        returnList.add(GroupedLotReturn(
          originalLot: lot,
          stations: stationInfos,
          batches: lotBatches,
          purchasedQuantity: purchasedQty,
          netQuantity: netQty,
          alreadyReturnedQuantity: returnedQty,
          availableQuantity: availableQty,
          unitLabel: unitLabel,
        ));
      }

      if (returnList.isEmpty && allLots.isNotEmpty) {
        final Map<String, double> lotReturnedMap = {};
        for (final h in history) {
          final lid = h['lot_receipt_id']?.toString() ?? '';
          final retQty = (h['returned_quantity'] as num?)?.toDouble() ?? 0.0;
          lotReturnedMap[lid] = (lotReturnedMap[lid] ?? 0.0) + retQty;
        }

        for (final lot in allLots) {
          if (!lot.isConfirmed) continue;
          final lotId = lot.id ?? '';
          final lotNum = lot.lotNumber;
          final netQty = lot.netWarehouseQuantity;
          final purchasedQty = lot.grossPurchaseQuantity;
          final returnedQty = lotReturnedMap[lotId] ?? 0.0;
          final availableQty = (netQty - returnedQty).clamp(0.0, double.infinity);
          if (availableQty <= 0) continue;

          final lProdName = (lot.productName ?? '').trim();
          final lFruitId = lot.fruitTypeId?.toString();

          final matchedBatches = allBatches.where((b) {
            final bCode = b['code'] as String;
            final bName = (b['pname'] as String).trim();
            final codeMatch = (bCode == lotNum || bCode == lotId);
            if (!codeMatch) return false;

            if (lProdName.isNotEmpty && bName.isNotEmpty) {
              if (bName != lProdName && !bName.contains(lProdName) && !lProdName.contains(bName)) {
                return false;
              }
            }

            final bFruitId = b['fruit_type_id']?.toString();
            if (bFruitId != null && lFruitId != null && bFruitId != lFruitId) {
              return false;
            }

            return true;
          }).toList();
          final List<LotBatchInfo> lotBatches = [];
          final Map<String, double> stationQtyMap = {};

          for (final b in matchedBatches) {
            final sid = b['sid'] as String;
            final qty = b['qty'] as double;
            if (qty > 0) {
              stationQtyMap[sid] = (stationQtyMap[sid] ?? 0) + qty;
              lotBatches.add(LotBatchInfo(
                b['id'] as int,
                sid,
                stationNames[sid] ?? 'محطة $sid',
                qty,
              ));
            }
          }

          final stationInfos = <LotStationInfo>[];
          for (final entry in stationQtyMap.entries) {
            stationInfos.add(LotStationInfo(
              entry.key,
              stationNames[entry.key] ?? 'محطة ${entry.key}',
              entry.value,
            ));
          }

          if (stationInfos.isEmpty) {
            final stId = lot.stationId ?? '1';
            stationInfos.add(LotStationInfo(
              stId,
              stationNames[stId] ?? 'المحطة الرئيسية',
              availableQty,
            ));
          }

          returnList.add(GroupedLotReturn(
            originalLot: lot,
            stations: stationInfos,
            batches: lotBatches,
            purchasedQuantity: purchasedQty,
            netQuantity: netQty,
            alreadyReturnedQuantity: returnedQty,
            availableQuantity: availableQty,
            unitLabel: lot.unitLabel,
          ));
        }
      }

      _lots = returnList;
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

  Future<void> _exportReturnsPdf() async {
    final dataToExport = _filteredHistory.isNotEmpty ? _filteredHistory : _historyReturns;
    if (dataToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد عمليات مرتجع متاحة للطباعة', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    try {
      await CropReturnPdfService.printReturnsReport(
        context,
        dataToExport,
        filterQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء إعداد ملف PDF: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _printSingleReturn(Map<String, dynamic> ret) async {
    try {
      await CropReturnPdfService.printSingleReturn(context, ret);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تجهيز إذن المرتجع للطباعة: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _showReturnDialog(GroupedLotReturn item) async {
    final lot = item.originalLot;
    final batches = item.batches;

    String? selectedStationId;
    int? selectedBatchId;
    if (batches.length == 1) {
      selectedStationId = batches.first.stationId;
      selectedBatchId = batches.first.batchId;
    } else if (batches.isNotEmpty) {
      selectedStationId = batches.first.stationId;
      selectedBatchId = batches.first.batchId;
    } else {
      selectedStationId = item.stations.firstOrNull?.stationId ?? lot.stationId;
    }

    CostCenter? targetCc;
    try {
      targetCc = await ProductCostCenterSyncService.instance.resolveCropCostCenter(
        fruitTypeId: lot.fruitTypeId,
        cropName: lot.productName ?? 'محصول',
      );
    } catch (_) {}

    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool saving = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            LotBatchInfo? selectedBatch;
            if (selectedBatchId != null) {
              selectedBatch = batches.where((b) => b.batchId == selectedBatchId).firstOrNull;
            }
            final double batchStock = selectedBatch?.remainingQuantity ?? item.availableQuantity;
            final double maxQty = (batchStock < item.availableQuantity) ? batchStock : item.availableQuantity;
            final unitLabel = item.unitLabel;

            final isDark = AppTheme.isDark(context);
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: isDark ? const Color(0xFF0D2137) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'مرتجع ${lot.productName}',
                        style: TextStyle(
                          color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المورد: ${lot.supplierName ?? ''}',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('الكمية الصافية المخزنية:',
                                    style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                Text(_formatQty(item.netQuantity, unitLabel),
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo')),
                              ],
                            ),
                            if (item.purchasedQuantity > item.netQuantity) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('الوزن القائم (الإجمالي):',
                                      style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                  Text(_formatQty(item.purchasedQuantity, unitLabel),
                                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                            if (item.alreadyReturnedQuantity > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('الكمية المرتجعة سابقاً:',
                                      style: TextStyle(color: AppTheme.danger, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                  Text(_formatQty(item.alreadyReturnedQuantity, unitLabel),
                                      style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo')),
                                ],
                              ),
                            ],
                            Divider(color: isDark ? const Color(0x33FFFFFF) : const Color(0xFFE2E8F0), height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('الكمية المتاحة للإرجاع:',
                                    style: TextStyle(color: isDark ? AppTheme.warning : const Color(0xFFD97706), fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                Text(_formatQty(maxQty, unitLabel),
                                    style: TextStyle(color: isDark ? AppTheme.warning : const Color(0xFFD97706), fontWeight: FontWeight.w900, fontSize: 14, fontFamily: 'Cairo')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (targetCc != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.success.withAlpha(80)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.account_tree_outlined, size: 16, color: AppTheme.success),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'مركز التكلفة: ${targetCc.displayTitle}',
                                  style: const TextStyle(color: AppTheme.success, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (batches.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('المحطة / الدفعة المخزنية:',
                            style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...batches.map((b) {
                          final isSelected = selectedBatchId == b.batchId;
                          return GestureDetector(
                            onTap: saving ? null : () {
                              setState(() {
                                selectedBatchId = b.batchId;
                                selectedStationId = b.stationId;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isDark ? AppTheme.primary.withAlpha(25) : const Color(0xFFE0F2FE))
                                    : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : (isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1)),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                    color: isSelected ? AppTheme.primary : (isDark ? AppTheme.textSecondary : Colors.black54),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(b.stationName,
                                            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text('الدفعة #${b.batchId}',
                                            style: TextStyle(color: isDark ? AppTheme.textSecondary.withAlpha(180) : Colors.black54, fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'رصيد الدفعة: ${_formatQty(b.remainingQuantity, unitLabel)}',
                                    style: TextStyle(
                                      color: isSelected ? (isDark ? AppTheme.warning : const Color(0xFFD97706)) : (isDark ? AppTheme.textSecondary : Colors.black87),
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: qtyCtrl,
                        enabled: !saving,
                        decoration: InputDecoration(
                          labelText: 'الكمية المرتجعة * ($unitLabel)',
                          hintText: 'الحد الأقصى ${_formatQty(maxQty, unitLabel)}',
                          labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          hintStyle: TextStyle(color: isDark ? AppTheme.textSecondary.withAlpha(120) : Colors.black54, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesCtrl,
                        enabled: !saving,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات المرتجع (اختياري)',
                          hintText: 'سبب المرتجع...',
                          labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          hintStyle: TextStyle(color: isDark ? AppTheme.textSecondary.withAlpha(120) : Colors.black54, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                        ),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: Text('إلغاء',
                        style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    onPressed: saving ? null : () async {
                      final val = double.tryParse(qtyCtrl.text) ?? 0;
                      if (val <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال كمية إرجاع صحيحة أكبر من صفر'),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                        return;
                      }
                      if (val > maxQty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('الكمية تتجاوز الرصيد المخزني المتاح للإرجاع (${_formatQty(maxQty, unitLabel)})'),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                        return;
                      }

                      setState(() => saving = true);
                      try {
                        final result = await _returnDao.processReturn(
                          lotId: lot.id!,
                          returnQuantity: val,
                          notes: notesCtrl.text.trim().isNotEmpty
                              ? notesCtrl.text.trim()
                              : (lot.supplierName != null && lot.supplierName!.isNotEmpty
                                  ? 'مرتجع شراء محصول للمورد: ${lot.supplierName} - لوط #${lot.lotNumber.isNotEmpty ? lot.lotNumber : lot.id}'
                                  : null),
                          stationId: selectedStationId,
                          batchId: selectedBatchId,
                          costCenterId: targetCc?.code ?? targetCc?.id,
                        );
                        if (context.mounted) {
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
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: AppTheme.danger),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('تأكيد المرتجع', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
    final isDark = AppTheme.isDark(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Container(
          decoration: isDark
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
                  ),
                )
              : null,
          child: Column(children: [
            _buildHeader(isDark),
            _buildTabSelector(isDark),
            _buildSearchBar(isDark),
            Expanded(child: _buildBody(isDark)),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16, left: 20, right: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(50) : const Color(0xFFCBD5E1))),
          ),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_forward, color: isDark ? Colors.white : Colors.black),
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.danger.withAlpha(30), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.assignment_return_outlined, color: AppTheme.danger, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'مرتجع شراء المحاصيل',
                style: TextStyle(
                  color: isDark ? AppTheme.textPrimary : Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            if (_historyReturns.isNotEmpty) ...[
              ElevatedButton.icon(
                onPressed: _exportReturnsPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 17, color: Colors.white),
                label: const Text(
                  'طباعة التقرير',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildTabSelector(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x2205192D) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'المرتجعات المتاحة',
              count: _lots.length,
              isSelected: _selectedTab == 0,
              icon: Icons.inventory_2_outlined,
              isDark: isDark,
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
              isDark: isDark,
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
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.primary.withAlpha(40) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primary : (isDark ? AppTheme.textSecondary : Colors.black87),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? (isDark ? Colors.white : Colors.black) : (isDark ? AppTheme.textSecondary : Colors.black87),
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : (isDark ? const Color(0x33FFFFFF) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _searchController,
        onChanged: (v) {
          _searchQuery = v;
          _applyFilter();
        },
        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: _selectedTab == 0
              ? 'بحث باسم المحصول، المورد أو الكود...'
              : 'بحث في سجل المرتجعات باللوط، المورد، أو القيد...',
          hintStyle: TextStyle(color: isDark ? AppTheme.textSecondary.withAlpha(120) : Colors.black54, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
          prefixIcon: Icon(Icons.search, color: isDark ? AppTheme.textSecondary.withAlpha(120) : Colors.black54, size: 18),
          filled: true,
          fillColor: isDark ? const Color(0x3805192D) : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_selectedTab == 0) {
      return _buildAvailableReturnsList(isDark);
    } else {
      return _buildHistoryReturnsList(isDark);
    }
  }

  Widget _buildAvailableReturnsList(bool isDark) {
    if (_filteredLots.isEmpty) {
      return Center(
        child: Text('لا توجد محاصيل قابلة للارتجاع حالياً',
            style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      itemCount: _filteredLots.length,
      itemBuilder: (context, index) {
        final item = _filteredLots[index];
        final lot = item.originalLot;
        final stationCount = item.stations.length;
        final unitLabel = item.unitLabel;
        return Card(
          color: isDark ? const Color(0x3805192D) : Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1)),
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
                        Text(lot.productName ?? 'غير معروف',
                            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                        const SizedBox(height: 4),
                        Text('المورد: ${lot.supplierName ?? 'بدون مورد'}',
                            style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppTheme.primary.withAlpha(25), borderRadius: BorderRadius.circular(12)),
                              child: Text('رقم الشراء: ${lot.lotNumber}',
                                  style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                              ),
                              child: Text('الكمية الصافية المخزنية: ${_formatQty(item.netQuantity, unitLabel)}',
                                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            ),
                            if (item.purchasedQuantity > item.netQuantity)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0x0DFFFFFF) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFE2E8F0)),
                                ),
                                child: Text('القائم: ${_formatQty(item.purchasedQuantity, unitLabel)}',
                                    style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                              ),
                            if (item.alreadyReturnedQuantity > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: AppTheme.danger.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                                child: Text('تم إرجاع: ${_formatQty(item.alreadyReturnedQuantity, unitLabel)}',
                                    style: const TextStyle(color: AppTheme.danger, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: item.stations.map((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.info.withAlpha(20) : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? AppTheme.info.withAlpha(40) : const Color(0xFFBAE6FD)),
                            ),
                            child: Text(
                              '${s.stationName} (${_formatQty(s.remainingQuantity, unitLabel)})',
                              style: TextStyle(color: isDark ? AppTheme.info : const Color(0xFF0369A1), fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                            ),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('المتاح للإرجاع',
                          style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      Text(_formatQty(item.availableQuantity, unitLabel),
                          style: TextStyle(color: isDark ? AppTheme.warning : const Color(0xFFD97706), fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Cairo')),
                      if (stationCount > 1) ...[
                        const SizedBox(height: 2),
                        Text('في $stationCount مخازن',
                            style: TextStyle(color: isDark ? AppTheme.info : const Color(0xFF0284C7), fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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

  Widget _buildHistoryReturnsList(bool isDark) {
    if (_filteredHistory.isEmpty) {
      return Center(
        child: Text('لا توجد عمليات مرتجع مسجلة حتى الآن',
            style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
          color: isDark ? const Color(0x3805192D) : Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1)),
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
                          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.print_outlined, color: AppTheme.primary, size: 18),
                          tooltip: 'طباعة إذن المرتجع',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 18,
                          onPressed: () => _printSingleReturn(ret),
                        ),
                      ],
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
                          Text('المورد: $supplierName',
                              style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('المحطة/المخزن: $stationName',
                              style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('رقم شراء المحصول: $lotNumber',
                              style: TextStyle(color: isDark ? AppTheme.info : const Color(0xFF0284C7), fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('ملاحظات: $notes',
                                style: TextStyle(color: isDark ? AppTheme.textSecondary.withAlpha(180) : Colors.black54, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${returnedQty.toStringAsFixed(1)} $unitLabel',
                          style: TextStyle(color: isDark ? AppTheme.warning : const Color(0xFFD97706), fontSize: 16, fontWeight: FontWeight.w900, fontFamily: 'Cairo'),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${returnValue.toStringAsFixed(2)} ${lotInfo?['currency'] == 'USD' ? '\$' : lotInfo?['currency'] == 'EUR' ? '€' : 'ج.م'}',
                          style: const TextStyle(color: AppTheme.danger, fontSize: 14, fontWeight: FontWeight.w900, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0), height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
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
                              color: isDark ? AppTheme.cyan.withAlpha(30) : const Color(0xFFECFEFF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? AppTheme.cyan.withAlpha(80) : const Color(0xFF06B6D4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long_outlined, color: isDark ? AppTheme.cyan : const Color(0xFF0E7490), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'عرض القيد المحاسبي',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.cyan : const Color(0xFF0E7490),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Print Single Return Voucher Button
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _printSingleReturn(ret),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.primary.withAlpha(30) : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? AppTheme.primary.withAlpha(80) : const Color(0xFF0284C7)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.print_outlined, color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'طباعة إذن المرتجع',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (jeId != null)
                      Text(
                        'قيد رقم #$jeId',
                        style: TextStyle(
                          color: isDark ? AppTheme.textSecondary.withAlpha(160) : Colors.black54,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
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
