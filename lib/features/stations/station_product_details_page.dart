import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/models/station_product_batch.dart';
import '../../data/dao/station_product_batch_dao.dart';
import '../../data/dao/station_product_dao.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/station_product_model.dart';

class StationProductDetailsPage extends StatefulWidget {
  final int stationId;
  final String stationName;
  final String stationCode;
  final String stationType;
  final String productName;
  final String productCode;
  final double quantity;
  final String currency;
  final String? rawMaterialId;
  final int? fruitTypeId;
  final String itemType;
  const StationProductDetailsPage({
    super.key,
    required this.stationId,
    required this.stationName,
    required this.stationCode,
    required this.stationType,
    required this.productName,
    required this.productCode,
    required this.quantity,
    this.currency = 'EGP',
    this.rawMaterialId,
    this.fruitTypeId,
    this.itemType = '',
  });

  @override
  State<StationProductDetailsPage> createState() =>
      _StationProductDetailsPageState();
}

class _StationProductDetailsPageState extends State<StationProductDetailsPage> {
  final _batchDao = StationProductBatchDao();
  final _stationProductDao = StationProductDao();
  List<StationProductBatch> _batches = [];
  bool _isLoading = true;
  double _currentQuantity = 0;
  late StreamSubscription _sub1;
  late StreamSubscription _sub2;

  static const int _lowStockThreshold = 3000;

  Color get _stockColor {
    if (_currentQuantity <= 0) return AppTheme.danger;
    if (_currentQuantity <= _lowStockThreshold) return AppTheme.warning;
    return AppTheme.success;
  }

  @override
  void initState() {
    super.initState();
    _currentQuantity = widget.quantity;
    _loadBatches();
    _sub1 =
        DataChangeEventBus.instance.itemsStream.listen((_) => _loadBatches());
    _sub2 = DataChangeEventBus.instance.stationsStream
        .listen((_) => _loadBatches());
  }

  @override
  void dispose() {
    _sub1.cancel();
    _sub2.cancel();
    super.dispose();
  }

  Future<void> _loadBatches() async {
    debugPrint(
        '📦 _loadBatches START: stationId=${widget.stationId}, productName=${widget.productName}, productCode=${widget.productCode}, quantity=${widget.quantity}, currency=${widget.currency}, itemType=${widget.itemType}');
    setState(() => _isLoading = true);
    try {
      final isFruit = widget.itemType == 'fruit' || widget.fruitTypeId != null;

      final results = await Future.wait([
        _batchDao.getBatches(
          stationId: widget.stationId,
          productName: isFruit ? '' : widget.productName,
          productCode: isFruit ? '' : widget.productCode,
          rawMaterialId: widget.rawMaterialId,
          fruitTypeId: widget.fruitTypeId,
          itemType: widget.itemType,
        ),
        _stationProductDao.findByStationAndItem(
          stationId: widget.stationId,
          itemType: widget.itemType,
          rawMaterialId: widget.rawMaterialId,
          fruitTypeId: widget.fruitTypeId,
          productCode: widget.productCode,
          productName: widget.productName,
        ),
        _batchDao.getAllBatchesIncludingConsumed(
          stationId: widget.stationId,
          productName: isFruit ? '' : widget.productName,
          productCode: isFruit ? '' : widget.productCode,
          rawMaterialId: widget.rawMaterialId,
          fruitTypeId: widget.fruitTypeId,
          itemType: widget.itemType,
        ),
      ]);

      List<StationProductBatch> fetchedBatches = results[0] as List<StationProductBatch>;
      List<StationProductBatch> fetchedAllBatches = results[2] as List<StationProductBatch>;

      if (isFruit && widget.fruitTypeId != null) {
        fetchedBatches = fetchedBatches.where((b) => b.fruitTypeId == widget.fruitTypeId).toList();
        fetchedAllBatches = fetchedAllBatches.where((b) => b.fruitTypeId == widget.fruitTypeId).toList();
      }

      _batches = fetchedBatches;
      final sp = results[1] as StationProductModel?;
      if (sp != null) {
        _currentQuantity = sp.quantity.toDouble();
      }
      final allBatchesForSync = fetchedAllBatches;
      debugPrint(
          '📦 _loadBatches QUERIES DONE: batches=${_batches.length}, sp=${sp != null ? 'found qty=${sp.quantity}' : 'NULL'}, allBatches=${allBatchesForSync.length}');
      if (_batches.isNotEmpty) {
        for (final b in _batches) {
          debugPrint(
              '📦   batch: id=${b.id} station=${b.stationId} product=${b.productName} qty=${b.quantity} remaining=${b.remainingQuantity} cost=${b.unitCost} currency=${b.currency} source=${b.sourceType}');
        }
      }

      final batchTotal =
          _batches.fold(0.0, (sum, b) => sum + b.remainingQuantity);
      debugPrint(
          '📦 _loadBatches: productName=${widget.productName}, stationId=${widget.stationId}, _currentQuantity=$_currentQuantity, batchTotal=$batchTotal, batches=${_batches.length}');

      // Reconciliation: if station_products.quantity > batch total, try to
      // create individual batches from purchase_invoice_items instead of one
      // big merged batch.
      if (!isFruit && _currentQuantity > batchTotal && _currentQuantity > 0 && _batches.isEmpty) {
        debugPrint('📦 _loadBatches: Reconciliation needed, checking purchase_invoice_items...');
        
        // Find purchase invoice items for this product that don't have
        // corresponding station_product_batches yet
        try {
          final productCode = widget.productCode;
          final rawMatId = widget.rawMaterialId;
          List<Map<String, dynamic>> purchaseItems = [];
          
          if (rawMatId != null && rawMatId.isNotEmpty) {
            purchaseItems = await Supabase.instance.client
                .from('purchase_invoice_items')
                .select('id, quantity, unit_cost, exchange_rate, invoice_id, purchase_invoices!inner(supplier_id, currency, status, suppliers(name))')
                .eq('station_id', widget.stationId)
                .eq('raw_material_id', rawMatId)
                .eq('purchase_invoices.status', 'confirmed')
                .order('created_at', ascending: true);
          } else if (productCode.isNotEmpty) {
            purchaseItems = await Supabase.instance.client
                .from('purchase_invoice_items')
                .select('id, quantity, unit_cost, exchange_rate, invoice_id, purchase_invoices!inner(supplier_id, currency, status, suppliers(name))')
                .eq('station_id', widget.stationId)
                .or('raw_material_id.eq.$productCode')
                .eq('purchase_invoices.status', 'confirmed')
                .order('created_at', ascending: true);
          }
          
          if (purchaseItems.isEmpty) {
            // Fallback: try matching by product code in raw_materials
            try {
              final rmRows = await Supabase.instance.client
                  .from('raw_materials')
                  .select('id')
                  .eq('code', productCode)
                  .limit(1);
              if (rmRows.isNotEmpty) {
                final rmId = rmRows.first['id'];
                purchaseItems = await Supabase.instance.client
                    .from('purchase_invoice_items')
                    .select('id, quantity, unit_cost, exchange_rate, invoice_id, purchase_invoices!inner(supplier_id, currency, status, suppliers(name))')
                    .eq('raw_material_id', rmId)
                    .eq('purchase_invoices.status', 'confirmed')
                    .order('created_at', ascending: true);
              }
            } catch (_) {}
          }
          
          if (purchaseItems.isNotEmpty) {
            debugPrint('📦 _loadBatches: Found ${purchaseItems.length} purchase items to create batches from');
            
            // Get existing batch purchase_invoice_ids to avoid duplicates
            final existingBatchInvoiceIds = allBatchesForSync
                .where((b) => b.sourceType == 'purchase')
                .map((b) => b.purchaseInvoiceId)
                .where((id) => id != null)
                .toSet();
            
            for (final pi in purchaseItems) {
              final invoiceId = pi['invoice_id']?.toString();
              if (invoiceId != null && existingBatchInvoiceIds.contains(int.tryParse(invoiceId))) {
                continue; // Skip if batch already exists for this invoice
              }
              
              final qty = (pi['quantity'] as num?)?.toDouble() ?? 0;
              if (qty <= 0) continue;
              
              final unitCost = (pi['unit_cost'] as num?)?.toDouble() ?? 0;
              final exchangeRate = (pi['exchange_rate'] as num?)?.toDouble() ?? 1.0;
              final invoice = pi['purchase_invoices'];
              final currency = (invoice is Map ? invoice['currency']?.toString() : null) ?? widget.currency;
              final supplier = invoice is Map ? invoice['suppliers'] : null;
              final supplierName = supplier is Map ? (supplier['name']?.toString() ?? '') : '';
              final purchaseInvoiceId = invoice is Map ? (invoice['id'] as num?)?.toInt() : (pi['invoice_id'] as num?)?.toInt();
              
              await _batchDao.insertBatch(
                stationId: widget.stationId,
                productName: widget.productName,
                productCode: widget.productCode,
                quantity: qty,
                unitCost: unitCost,
                currency: currency,
                exchangeRate: exchangeRate,
                sourceType: 'purchase',
                supplierName: supplierName,
                purchaseInvoiceId: purchaseInvoiceId,
              );
            }
            
            _batches = await _batchDao.getBatches(
                stationId: widget.stationId, productName: widget.productName);
            debugPrint('📦 _loadBatches: After individual batch creation, batches=${_batches.length}');
          }
        } catch (e) {
          debugPrint('⚠️ _loadBatches: purchase_invoice_items query failed: $e');
        }
        
        // If we still don't have batches, create a single fallback
        if (_batches.isEmpty && _currentQuantity > 0) {
          debugPrint('📦 _loadBatches: Creating single fallback batch for quantity=$_currentQuantity');
          double unitCost = 0;
          try {
            final fruitTypes = await FruitTypeDao().getAllWithPrices();
            for (final ft in fruitTypes) {
              if (ft.name == widget.productName) {
                unitCost = ft.latestPurchasePrice ?? ft.averagePurchasePrice ?? 0;
                break;
              }
            }
          } catch (_) {}
          try {
            await _batchDao.insertBatch(
              stationId: widget.stationId,
              productName: widget.productName,
              productCode: widget.productCode,
              quantity: _currentQuantity,
              unitCost: unitCost,
              currency: widget.currency,
              exchangeRate: 1.0,
              sourceType: 'purchase',
            );
          } catch (insertErr) {
            debugPrint('❌ _loadBatches: fallback insertBatch FAILED: $insertErr');
          }
          _batches = await _batchDao.getBatches(
              stationId: widget.stationId, productName: widget.productName);
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('⚠️ _loadBatches error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadBatches,
                  color: AppTheme.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                      //  _buildStockOverview(),
                        const SizedBox(height: 20),
                        _buildBatchesTable(),
                      ],
                    ),
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
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _stockColor.withValues(alpha: 0.25),
                _stockColor.withValues(alpha: 0.08)
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _currentQuantity <= _lowStockThreshold
                ? Icons.warning_amber_rounded
                : Icons.inventory_2_outlined,
            color: _stockColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.productName,
                    style: TextStyle(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
                Row(
                  children: [
                    Text(widget.stationName,
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 13,
                            fontFamily: 'Cairo')),
                    if (widget.productCode.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('•',
                          style: TextStyle(
                              color:
                                  AppTheme.textSecondary.withValues(alpha: 0.5),
                              fontSize: 13)),
                      const SizedBox(width: 8),
                      Text(widget.productCode,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              fontFamily: 'Cairo')),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _glass({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppTheme.glassCard(),
          child: child,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.2),
                AppTheme.accent.withValues(alpha: 0.1)
              ],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildStockOverview() {
    final isLow = _currentQuantity <= _lowStockThreshold;
    final totalValue = _batches.fold(0.0, (sum, b) => sum + b.batchTotalCost);
    debugPrint(
        '📊 _buildStockOverview: _currentQuantity=$_currentQuantity, totalValue=$totalValue, _batches.length=${_batches.length}');

    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('ملخص المخزون', Icons.analytics_outlined),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _stockColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _stockColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _currentQuantity <= 0
                      ? 'نفذت الكمية'
                      : (_currentQuantity <= _lowStockThreshold
                          ? 'رصيد منخفض'
                          : 'رصيد آمن'),
                  style: TextStyle(
                      color: _stockColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stockStat('الكمية الحالية بالمخزن',
                  AppUtils.formatNumber(_currentQuantity), '', _stockColor),
              const SizedBox(width: 12),
              _stockStat(
                  'إجمالي قيمة المخزون',
                  '${AppUtils.formatNumber(totalValue)} ${widget.currency}',
                  '',
                  AppTheme.accent),
            ],
          ),
          if (isLow && _currentQuantity > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'الكمية أقل من $_lowStockThreshold — يجب إعادة الطلب',
                      style: const TextStyle(
                          color: AppTheme.warning,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _currentQuantity > 0
                  ? (_currentQuantity / _lowStockThreshold).clamp(0.0, 1.0)
                  : 0.0,
              minHeight: 14,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(_stockColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockStat(String label, String value, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Cairo')),
            const SizedBox(height: 6),
            Row(
              textBaseline: TextBaseline.alphabetic,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              children: [
                Flexible(
                  child: Text(value,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(unit,
                      style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontFamily: 'Cairo')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchesTable() {
    final totalRemaining =
        _batches.fold(0.0, (sum, b) => sum + b.remainingQuantity);
    final totalValue = _batches.fold(0.0, (sum, b) => sum + b.batchTotalCost);
    debugPrint(
        '🎨 _buildBatchesTable: _batches.length=${_batches.length}, totalRemaining=$totalRemaining, totalValue=$totalValue, _isLoading=$_isLoading');
    for (int i = 0; i < _batches.length; i++) {
      final b = _batches[i];
      debugPrint(
          '🎨   [$i] id=${b.id} product=${b.productName} qty=${b.quantity} remaining=${b.remainingQuantity} cost=${b.unitCost} source=${b.sourceType}');
    }

    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('الدفعات', Icons.local_shipping_outlined),
          const SizedBox(height: 8),
          const Text(
              'كل مشتري بالتاريخ والسعر — أول كمية اشتريت هي أول حاجة هتسحب منها',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 16),
          if (_isLoading)
            const SizedBox(
                height: 80,
                child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primary)))
          else if (_batches.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.local_shipping_outlined,
                        size: 48,
                        color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    const Text('لا توجد دفعات مسجلة',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 14)),
                  ],
                ),
              ),
            )
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 800,
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    color: const Color(0x1A00E5FF),
                    child: const Row(
                      children: [
                        SizedBox(
                            width: 36,
                            child: Text('#',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12))),
                        SizedBox(
                            width: 80,
                            child: Text('التاريخ',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12))),
                        SizedBox(
                            width: 120,
                            child: Text('المصدر',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12))),
                        SizedBox(
                            width: 60,
                            child: Text('FIFO',
                                style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 75,
                            child: Text('الكمية',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 75,
                            child: Text('المتبقي',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 80,
                            child: Text('سعر الصرف',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 100,
                            child: Text('سعر الوحدة',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 100,
                            child: Text('الإجمالي',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                  ..._batches.asMap().entries.map((e) {
                    final i = e.key;
                    final batch = e.value;
                    final isEven = i % 2 == 0;
                    final isFullyConsumed = batch.remainingQuantity <= 0;
                    String sourceLabel = 'مشتريات';
                    if (batch.supplierName.isNotEmpty) {
                      sourceLabel = batch.supplierName;
                    } else if (batch.sourceType == 'opening') {
                      sourceLabel = 'رصيد افتتاحي';
                    } else if (batch.sourceType == 'transfer') {
                      sourceLabel = batch.sourceStationName.isNotEmpty
                          ? 'تحويل من ${batch.sourceStationName}'
                          : 'تحويل';
                    } else {
                      sourceLabel = 'مشتريات';
                    }
                    if (batch.invoiceNumber != null && batch.invoiceNumber!.isNotEmpty) {
                      sourceLabel += ' | فاتورة: ${batch.invoiceNumber}';
                    }
                    final rowTotal = batch.remainingQuantity * batch.unitCost;
                    final isFirstAvailable = !isFullyConsumed &&
                        _batches.indexWhere((b) => b.remainingQuantity > 0) ==
                            i;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      color: isFirstAvailable
                          ? AppTheme.primary.withValues(alpha: 0.08)
                          : (isEven
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.white.withValues(alpha: 0.05)),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    decoration: isFullyConsumed
                                        ? TextDecoration.lineThrough
                                        : null)),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                                _formatDate(batch.sourceDate.isNotEmpty
                                    ? batch.sourceDate
                                    : batch.createdAt),
                                style: TextStyle(
                                    color: isFullyConsumed
                                        ? AppTheme.textSecondary
                                        : Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    decoration: isFullyConsumed
                                        ? TextDecoration.lineThrough
                                        : null)),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(sourceLabel,
                                style: TextStyle(
                                    color: isFullyConsumed
                                        ? AppTheme.textSecondary
                                        : Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                          ),
                          SizedBox(
                            width: 60,
                            child: isFirstAvailable
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [
                                        AppTheme.primary,
                                        AppTheme.accent
                                      ]),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('FIFO',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center),
                                  )
                                : isFullyConsumed
                                    ? const Text('—',
                                        style: TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontFamily: 'Cairo',
                                            fontSize: 11),
                                        textAlign: TextAlign.center)
                                    : const SizedBox.shrink(),
                          ),
                          SizedBox(
                            width: 75,
                            child: Text(AppUtils.formatNumber(batch.quantity),
                                style: TextStyle(
                                    color: isFullyConsumed
                                        ? AppTheme.textSecondary
                                        : Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center),
                          ),
                          SizedBox(
                            width: 75,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: batch.remainingQuantity > 0
                                    ? AppTheme.success.withValues(alpha: 0.1)
                                    : AppTheme.textSecondary
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                  AppUtils.formatNumber(
                                      batch.remainingQuantity),
                                  style: TextStyle(
                                      color: batch.remainingQuantity > 0
                                          ? AppTheme.success
                                          : AppTheme.textSecondary,
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                                batch.exchangeRate == 1.0
                                    ? '—'
                                    : batch.exchangeRate.toStringAsFixed(4),
                                style: TextStyle(
                                    color: batch.exchangeRate == 1.0
                                        ? AppTheme.textSecondary
                                        : AppTheme.info,
                                    fontFamily: 'Cairo',
                                    fontSize: 11),
                                textAlign: TextAlign.center),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                                '${AppUtils.formatNumber(batch.unitCost)} ${widget.currency}',
                                style: TextStyle(
                                    color: isFullyConsumed
                                        ? AppTheme.textSecondary
                                        : AppTheme.accent,
                                    fontFamily: 'Cairo',
                                    fontSize: 12),
                                textAlign: TextAlign.center),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                                '${AppUtils.formatNumber(rowTotal)} ${widget.currency}',
                                style: TextStyle(
                                    color: isFullyConsumed
                                        ? AppTheme.textSecondary
                                        : Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                    );
                  }),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.1),
                    AppTheme.accent.withValues(alpha: 0.05)
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.summarize_outlined,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Text('الإجمالي',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                    const SizedBox(width: 16),
                    Text('${AppUtils.formatNumber(totalRemaining)} وحدة',
                        style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo')),
                    const SizedBox(width: 16),
                    Text(
                        '${AppUtils.formatNumber(totalValue)} ${widget.currency}',
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                    const SizedBox(width: 8),
                    Text('${_batches.length} دفعة',
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
