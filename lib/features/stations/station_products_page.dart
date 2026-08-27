import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/models/station_product_model.dart';
import '../../data/models/fruit_type_model.dart';
import '../../data/dao/station_product_dao.dart';
import '../../data/dao/station_product_batch_dao.dart';
import '../../data/models/station_product_batch.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/dao/raw_material_dao.dart';
import 'station_stock_report_service.dart';

class StationProductsPage extends StatefulWidget {
  final int stationId;
  final String stationName;
  final String stationCode;
  final String stationType;
  const StationProductsPage(
      {super.key,
      required this.stationId,
      required this.stationName,
      required this.stationCode,
      required this.stationType});

  @override
  State<StationProductsPage> createState() => _StationProductsPageState();
}

class _StationProductsPageState extends State<StationProductsPage>
    with SingleTickerProviderStateMixin {
  final _dao = StationProductDao();
  final _batchDao = StationProductBatchDao();
  final _fruitTypeDao = FruitTypeDao();
  final _rawMaterialDao = RawMaterialDao();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  List<StationProductModel> _products = [];
  List<StationProductModel> _filteredProducts = [];
  Map<String, FruitTypeModel> _fruitTypeMap = {};
  Map<String, RawMaterialModel> _rawMaterialMap = {};
  Map<String, double> _batchValues = {};
  Map<String, double> _batchRemainingQty = {};
  Map<String, double> _weightPerCartonMap = {};
  Map<String, String> _productDisplayCurrency = {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isGridView = true;
  String _searchQuery = '';
  String? _selectedCategory; // null = الكل, 'crops' = محاصيل, 'raw' = مواد خام
  late StreamSubscription _sub1;
  late StreamSubscription _sub2;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const int _lowStockThreshold = 3000;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadData();
    _sub1 = DataChangeEventBus.instance.itemsStream.listen((_) => _loadData());
    _sub2 =
        DataChangeEventBus.instance.stationsStream.listen((_) => _loadData());
  }

  @override
  void dispose() {
    _sub1.cancel();
    _sub2.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _dao.getByStation(widget.stationId),
        _fruitTypeDao.getAllWithPrices(),
        _batchDao.getAllBatches(stationId: widget.stationId),
        _rawMaterialDao.getAll(),
      ]);
      _products = results[0] as List<StationProductModel>;
      final fruitTypes = results[1] as List<FruitTypeModel>;
      final batches = results[2] as List<StationProductBatch>;
      final rawMaterials = results[3] as List<RawMaterialModel>;
      _fruitTypeMap = {
        for (final ft in fruitTypes) ...{
          'fruit_${ft.id}': ft,
          if (ft.code.isNotEmpty) 'fruit_code_${ft.code}': ft,
          'fruit_name_${ft.name.trim().toLowerCase()}': ft,
          ft.name: ft,
        }
      };
      _rawMaterialMap = {
        for (final rm in rawMaterials) ...{
          'material_${rm.id}': rm,
          if (rm.code.isNotEmpty) 'material_code_${rm.code}': rm,
          'material_name_${rm.name.trim().toLowerCase()}': rm,
          rm.name: rm,
        }
      };

      _weightPerCartonMap = {};
      try {
        final allLrs = await Supabase.instance.client
            .from('lot_receipts')
            .select(
                'product_name, carton_count, net_weight_kg, weight_per_carton_kg')
            .eq('station_id', widget.stationId.toString());
        for (final lr in allLrs) {
          final name = lr['product_name'] as String? ?? '';
          if (name.isEmpty) continue;
          final wpc = (lr['weight_per_carton_kg'] as num?)?.toDouble() ?? 0.0;
          if (wpc > 0) {
            _weightPerCartonMap[name] = wpc;
          } else {
            final cc = (lr['carton_count'] as num?)?.toDouble() ?? 0.0;
            final nw = (lr['net_weight_kg'] as num?)?.toDouble() ?? 0.0;
            if (cc > 0 && nw > 0) {
              _weightPerCartonMap[name] = nw / cc;
            }
          }
        }
      } catch (_) {}

      _batchValues = {};
      _batchRemainingQty = {};
      _productDisplayCurrency = {};
      for (final b in batches) {
        final value = b.remainingQuantity * b.unitCost;
        final itemKey = b.itemKey;

        _batchValues[itemKey] = (_batchValues[itemKey] ?? 0) + value;
        _batchRemainingQty[itemKey] =
            (_batchRemainingQty[itemKey] ?? 0) + b.remainingQuantity;

        if (b.remainingQuantity > 0 ||
            _productDisplayCurrency[itemKey] == null) {
          _productDisplayCurrency[itemKey] = b.currency;
        }
      }

      for (final p in _products) {
        final isFruit = p.itemType == 'fruit' || p.fruitTypeId != null;
        if (isFruit) {
          final ft = (p.fruitTypeId != null ? _fruitTypeMap['fruit_${p.fruitTypeId}'] : null) ??
              (p.productCode.isNotEmpty ? _fruitTypeMap['fruit_code_${p.productCode}'] : null) ??
              _fruitTypeMap['fruit_name_${p.productName.trim().toLowerCase()}'];
          if (ft != null && ft.currency.isNotEmpty) {
            _productDisplayCurrency[p.itemKey] = ft.currency;
            if (p.productCode.isNotEmpty) {
              _productDisplayCurrency['fruit_code_${p.productCode}'] = ft.currency;
            }
            _productDisplayCurrency['fruit_name_${p.productName.trim().toLowerCase()}'] = ft.currency;
          }
        } else {
          final rm = (p.rawMaterialId != null ? _rawMaterialMap['material_${p.rawMaterialId}'] : null) ??
              (p.productCode.isNotEmpty ? _rawMaterialMap['material_code_${p.productCode}'] : null) ??
              _rawMaterialMap['material_name_${p.productName.trim().toLowerCase()}'];
          if (rm != null && rm.currency.isNotEmpty) {
            _productDisplayCurrency[p.itemKey] = rm.currency;
            if (p.productCode.isNotEmpty) {
              _productDisplayCurrency['material_code_${p.productCode}'] = rm.currency;
            }
            _productDisplayCurrency['material_name_${p.productName.trim().toLowerCase()}'] = rm.currency;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('خطأ في تحميل البيانات: $e');
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    try {
      final results = await Future.wait([
        _dao.getByStation(widget.stationId),
        _fruitTypeDao.getAllWithPrices(),
        _batchDao.getAllBatches(stationId: widget.stationId),
        _rawMaterialDao.getAll(),
      ]);
      _products = results[0] as List<StationProductModel>;
      final fruitTypes = results[1] as List<FruitTypeModel>;
      final batches = results[2] as List<StationProductBatch>;
      final rawMaterials = results[3] as List<RawMaterialModel>;
      _fruitTypeMap = {
        for (final ft in fruitTypes) ...{
          'fruit_${ft.id}': ft,
          if (ft.code.isNotEmpty) 'fruit_code_${ft.code}': ft,
          'fruit_name_${ft.name.trim().toLowerCase()}': ft,
          ft.name: ft,
        }
      };
      _rawMaterialMap = {
        for (final rm in rawMaterials) ...{
          'material_${rm.id}': rm,
          if (rm.code.isNotEmpty) 'material_code_${rm.code}': rm,
          'material_name_${rm.name.trim().toLowerCase()}': rm,
          rm.name: rm,
        }
      };

      _weightPerCartonMap = {};
      try {
        final allLrs = await Supabase.instance.client
            .from('lot_receipts')
            .select(
                'product_name, carton_count, net_weight_kg, weight_per_carton_kg')
            .eq('station_id', widget.stationId.toString());
        for (final lr in allLrs) {
          final name = lr['product_name'] as String? ?? '';
          if (name.isEmpty) continue;
          final wpc = (lr['weight_per_carton_kg'] as num?)?.toDouble() ?? 0.0;
          if (wpc > 0) {
            _weightPerCartonMap[name] = wpc;
          } else {
            final cc = (lr['carton_count'] as num?)?.toDouble() ?? 0.0;
            final nw = (lr['net_weight_kg'] as num?)?.toDouble() ?? 0.0;
            if (cc > 0 && nw > 0) {
              _weightPerCartonMap[name] = nw / cc;
            }
          }
        }
      } catch (_) {}

      _batchValues = {};
      _batchRemainingQty = {};
      _productDisplayCurrency = {};
      for (final b in batches) {
        final value = b.remainingQuantity * b.unitCost;
        final itemKey = b.itemKey;

        _batchValues[itemKey] = (_batchValues[itemKey] ?? 0) + value;
        _batchRemainingQty[itemKey] =
            (_batchRemainingQty[itemKey] ?? 0) + b.remainingQuantity;

        if (b.remainingQuantity > 0 ||
            _productDisplayCurrency[itemKey] == null) {
          _productDisplayCurrency[itemKey] = b.currency;
        }
      }

      for (final p in _products) {
        final isFruit = p.itemType == 'fruit' || p.fruitTypeId != null;
        if (isFruit) {
          final ft = (p.fruitTypeId != null ? _fruitTypeMap['fruit_${p.fruitTypeId}'] : null) ??
              (p.productCode.isNotEmpty ? _fruitTypeMap['fruit_code_${p.productCode}'] : null) ??
              _fruitTypeMap['fruit_name_${p.productName.trim().toLowerCase()}'];
          if (ft != null && ft.currency.isNotEmpty) {
            _productDisplayCurrency[p.itemKey] = ft.currency;
            if (p.productCode.isNotEmpty) {
              _productDisplayCurrency['fruit_code_${p.productCode}'] = ft.currency;
            }
            _productDisplayCurrency['fruit_name_${p.productName.trim().toLowerCase()}'] = ft.currency;
          }
        } else {
          final rm = (p.rawMaterialId != null ? _rawMaterialMap['material_${p.rawMaterialId}'] : null) ??
              (p.productCode.isNotEmpty ? _rawMaterialMap['material_code_${p.productCode}'] : null) ??
              _rawMaterialMap['material_name_${p.productName.trim().toLowerCase()}'];
          if (rm != null && rm.currency.isNotEmpty) {
            _productDisplayCurrency[p.itemKey] = rm.currency;
            if (p.productCode.isNotEmpty) {
              _productDisplayCurrency['material_code_${p.productCode}'] = rm.currency;
            }
            _productDisplayCurrency['material_name_${p.productName.trim().toLowerCase()}'] = rm.currency;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _applyFilter();
        _isRefreshing = false;
        _searchQuery = '';
        _searchController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRefreshing = false);
      _showSnackBar('خطأ في التحديث: $e');
    }
  }

  void _applyFilter() {
    final q = _searchQuery.trim().toLowerCase();
    setState(() {
      _filteredProducts = _products.where((p) {
        final isFruit = p.itemType == 'fruit' || p.fruitTypeId != null;
        if (q.isNotEmpty) {
          final name = p.productName.toLowerCase();
          final code = p.productCode.toLowerCase();
          final ftCode = isFruit
              ? ((p.fruitTypeId != null ? _fruitTypeMap['fruit_${p.fruitTypeId}'] : null) ??
                      _fruitTypeMap['fruit_name_${p.productName.trim().toLowerCase()}'])
                  ?.code
                  .toLowerCase() ??
                  ''
              : '';
          final rmCode = !isFruit
              ? ((p.rawMaterialId != null ? _rawMaterialMap['material_${p.rawMaterialId}'] : null) ??
                      _rawMaterialMap['material_name_${p.productName.trim().toLowerCase()}'])
                  ?.code
                  .toLowerCase() ??
                  ''
              : '';
          if (!(name.contains(q) ||
              code.contains(q) ||
              ftCode.contains(q) ||
              rmCode.contains(q) ||
              name.replaceAll(' ', '').contains(q.replaceAll(' ', '')))) {
            return false;
          }
        }
        if (_selectedCategory == 'crops' && !isFruit) return false;
        if (_selectedCategory == 'raw' && isFruit) return false;
        return true;
      }).toList();
    });
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg, textDirection: TextDirection.rtl),
          duration: const Duration(seconds: 3),
          backgroundColor: AppTheme.primary),
    );
  }

  String _productCurrency(String productName) {
    final cleanName = productName.trim().toLowerCase();
    final ft = _fruitTypeMap['fruit_name_$cleanName'] ?? _fruitTypeMap[productName];
    if (ft != null) return ft.currency;
    final rm = _rawMaterialMap['material_name_$cleanName'] ?? _rawMaterialMap[productName];
    if (rm != null) return rm.currency;
    return 'EGP';
  }

  Future<void> _exportPdf() async {
    _showSnackBar('جاري إنشاء ملف PDF...');
    try {
      await StationStockReportService.exportPdf(
        stationId: widget.stationId,
        stationName: widget.stationName,
        stationCode: widget.stationCode,
        productDisplayCurrency: _productDisplayCurrency,
      );
      _showSnackBar('تم التصدير بنجاح');
    } catch (e) {
      _showSnackBar('خطأ في التصدير: $e');
    }
  }

  Future<void> _exportExcel() async {
    _showSnackBar('جاري إنشاء ملف Excel...');
    try {
      await StationStockReportService.exportExcel(
        stationId: widget.stationId,
        stationName: widget.stationName,
        stationCode: widget.stationCode,
        productDisplayCurrency: _productDisplayCurrency,
      );
      _showSnackBar('تم التصدير بنجاح');
    } catch (e) {
      _showSnackBar('خطأ في التصدير: $e');
    }
  }

  Color _stockColor(double qty) {
    if (qty <= 0) return AppTheme.danger;
    if (qty <= _lowStockThreshold) return AppTheme.warning;
    return AppTheme.success;
  }

  String _stockLabel(double qty) {
    if (qty <= 0) return 'خلص';
    if (qty <= _lowStockThreshold) return 'محتاج توريد';
    return 'متوفر';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 900;
              return Padding(
                padding: EdgeInsets.all(isMobile ? 12 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildCategoryTabs(),
                    const SizedBox(height: 12),
                    _buildSearchBar(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: AppTheme.primary))
                          : _isRefreshing
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: AppTheme.primary))
                              : _filteredProducts.isEmpty
                                  ? _buildEmptyState()
                                  : _isGridView
                                      ? _buildGridView(isMobile)
                                      : _buildTableView(),
                    ),
                  ],
                ),
              );
            },
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
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.store_outlined,
              color: AppTheme.accent, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.stationName,
                    style: TextStyle(
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
                Row(
                  children: [
                    Text(widget.stationCode,
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontFamily: 'Cairo',
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.stationType == 'main'
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                          widget.stationType == 'main' ? 'رئيسي' : 'فرعي',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: widget.stationType == 'main'
                                  ? AppTheme.primary
                                  : AppTheme.accent,
                              fontFamily: 'Cairo')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: 'تحديث',
          onPressed: _refreshData,
        ),
        // IconButton(
        //   icon:
        //       const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.danger),
        //   tooltip: 'تصدير PDF',
        //   onPressed: _exportPdf,
        // ),
        IconButton(
          icon: const Icon(Icons.table_chart_outlined, color: AppTheme.success),
          tooltip: 'تصدير Excel',
          onPressed: _exportExcel,
        ),
      ],
    );
  }

  Widget _viewToggleButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x3805192D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewButton(Icons.grid_view_rounded, _isGridView),
          _viewButton(Icons.table_rows_rounded, !_isGridView),
        ],
      ),
    );
  }

  Widget _viewButton(IconData icon, bool isActive) {
    return GestureDetector(
      onTap: () =>
          setState(() => _isGridView = icon == Icons.grid_view_rounded),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 18,
            color: isActive ? AppTheme.primary : AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (v) {
          _searchQuery = v;
          _applyFilter();
        },
        style: const TextStyle(
            color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
        decoration: InputDecoration(
          hintText: 'بحث بالاسم أو الكود...',
          hintStyle: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
              fontFamily: 'Cairo'),
          prefixIcon: Icon(Icons.search,
              color: AppTheme.textSecondary.withValues(alpha: 0.5), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _searchQuery = '';
                    _applyFilter();
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0x3805192D),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.glassBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.glassBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.primary)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchQuery.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off_outlined : Icons.inventory_2_outlined,
            size: 72,
            color: AppTheme.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'لا توجد نتائج' : 'لا توجد منتجات في هذا المخزن',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'جرب كلمة بحث مختلفة'
                : 'سيظهر المنتجات هنا بعد التحويل أو الشراء',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 13),
          ),
        ],
      ),
    );
  }

  double _getProductQuantity(StationProductModel p) {
    return _batchRemainingQty[p.itemKey] ?? p.quantity.toDouble();
  }

  Widget _buildCategoryTabs() {
    final totalQty = _products.fold<int>(
        0,
        (s, p) =>
            s + _getProductQuantity(p).toInt());
    final totalValueByCurrency = <String, double>{};
    int cropQty = 0;
    final cropValueByCurrency = <String, double>{};
    int rawQty = 0;
    final rawValueByCurrency = <String, double>{};
    for (final p in _products) {
      final isFruit = p.itemType == 'fruit' || p.fruitTypeId != null;
      final pKey = p.itemKey;
      final batchVal = _batchValues[pKey];
      final ft = isFruit
          ? ((p.fruitTypeId != null ? _fruitTypeMap['fruit_${p.fruitTypeId}'] : null) ??
              (p.productCode.isNotEmpty ? _fruitTypeMap['fruit_code_${p.productCode}'] : null) ??
              _fruitTypeMap['fruit_name_${p.productName.trim().toLowerCase()}'])
          : null;
      final rm = !isFruit
          ? ((p.rawMaterialId != null ? _rawMaterialMap['material_${p.rawMaterialId}'] : null) ??
              (p.productCode.isNotEmpty ? _rawMaterialMap['material_code_${p.productCode}'] : null) ??
              _rawMaterialMap['material_name_${p.productName.trim().toLowerCase()}'])
          : null;
      final price = ft?.latestPurchasePrice ??
          ft?.averagePurchasePrice ??
          rm?.defaultPurchasePrice ??
          0;
      final qty = _getProductQuantity(p);
      final val =
          (batchVal != null && batchVal > 0) ? batchVal : qty * price;
      final curr = _productDisplayCurrency[pKey] ??
          (isFruit ? (ft?.currency ?? 'EGP') : (rm?.currency ?? 'EGP'));
      totalValueByCurrency[curr] = (totalValueByCurrency[curr] ?? 0) + val;
      if (isFruit) {
        cropQty += qty.toInt();
        cropValueByCurrency[curr] = (cropValueByCurrency[curr] ?? 0) + val;
      } else {
        rawQty += qty.toInt();
        rawValueByCurrency[curr] = (rawValueByCurrency[curr] ?? 0) + val;
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _categoryTab(
              label: 'الكل',
              qty: totalQty,
              valueByCurrency: totalValueByCurrency,
              isSelected: _selectedCategory == null,
              onTap: () {
                _selectedCategory = null;
                _applyFilter();
              },
            ),
            _categoryTab(
              label: 'محاصيل',
              qty: cropQty,
              valueByCurrency: cropValueByCurrency,
              isSelected: _selectedCategory == 'crops',
              onTap: () {
                _selectedCategory = 'crops';
                _applyFilter();
              },
            ),
            _categoryTab(
              label: 'مواد خام',
              qty: rawQty,
              valueByCurrency: rawValueByCurrency,
              isSelected: _selectedCategory == 'raw',
              onTap: () {
                _selectedCategory = 'raw';
                _applyFilter();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryTab({
    required String label,
    required int qty,
    required Map<String, double> valueByCurrency,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final tabColor = AppTheme.primary;
    final currencies =
        valueByCurrency.entries.where((e) => e.value > 0).toList();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? tabColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? tabColor : AppTheme.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          constraints: const BoxConstraints(minWidth: 140),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? tabColor : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 12,
                          color:
                              isSelected ? tabColor : AppTheme.textSecondary),
                      const SizedBox(width: 3),
                      Text(
                        '$qty',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? tabColor : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (currencies.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    ...currencies.map((e) {
                      final v = e.value;
                      final formatted = v >= 1000000
                          ? '${(v / 1000000).toStringAsFixed(1)}M'
                          : v >= 1000
                              ? '${(v / 1000).toStringAsFixed(1)}K'
                              : v.toStringAsFixed(0);
                      return Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          '$formatted ${e.key}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                isSelected ? tabColor : AppTheme.textSecondary,
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(bool isMobile) {
    final crossAxisCount =
        isMobile ? 2 : (MediaQuery.of(context).size.width > 1400 ? 4 : 3);
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: isMobile ? 10 : 12,
        mainAxisSpacing: isMobile ? 10 : 12,
        childAspectRatio: isMobile ? 0.85 : 0.85,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) =>
          _buildProductCard(_filteredProducts[index], index),
    );
  }

  Widget _buildProductCard(StationProductModel product, int index) {
    final isFruit = product.itemType == 'fruit' || product.fruitTypeId != null;
    final pKey = product.itemKey;
    final displayQty = _getProductQuantity(product);
    final stockColor = _stockColor(displayQty);

    FruitTypeModel? fruitType;
    RawMaterialModel? rawMaterial;
    if (isFruit) {
      fruitType = (product.fruitTypeId != null ? _fruitTypeMap['fruit_${product.fruitTypeId}'] : null) ??
          (product.productCode.isNotEmpty ? _fruitTypeMap['fruit_code_${product.productCode}'] : null) ??
          _fruitTypeMap['fruit_name_${product.productName.trim().toLowerCase()}'];
    } else {
      rawMaterial = (product.rawMaterialId != null ? _rawMaterialMap['material_${product.rawMaterialId}'] : null) ??
          (product.productCode.isNotEmpty ? _rawMaterialMap['material_code_${product.productCode}'] : null) ??
          _rawMaterialMap['material_name_${product.productName.trim().toLowerCase()}'];
    }

    final isCarton = product.unit == 'carton' ||
        fruitType?.latestPurchaseMode == 'carton' ||
        fruitType?.purchaseMode == 'carton';
    final batchVal = _batchValues[pKey];
    final displayUnit = product.unit == 'carton' || product.unit == 'box' || rawMaterial?.unit == 'carton' || rawMaterial?.unit == 'box'
        ? 'كرتونة'
        : (isFruit 
            ? (isCarton ? 'كرتونة' : 'كجم') 
            : (rawMaterial?.unit ?? 'قطعة'));
    final wpc = isFruit
        ? (_weightPerCartonMap[product.productName] ?? fruitType?.latestWeightPerCartonKg ?? 0.0)
        : 0.0;
    final displayTitle = isFruit
        ? (fruitType?.name ?? product.productName)
        : (rawMaterial?.name ?? product.productName.replaceAll(' (مادة تعبئة)', ''));
    final inventoryValue = (batchVal != null && batchVal > 0)
        ? batchVal
        : displayQty *
            (fruitType?.latestPurchasePrice ??
                fruitType?.averagePurchasePrice ??
                rawMaterial?.defaultPurchasePrice ??
                0);
    final curr = _productDisplayCurrency[pKey] ??
        (isFruit ? (fruitType?.currency ?? 'EGP') : (rawMaterial?.currency ?? 'EGP'));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 30)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(0, 20 * (1 - value)), child: child),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: displayQty <= 0
                  ? const Color(0x20FF4444)
                  : displayQty <= _lowStockThreshold
                      ? const Color(0x20FFB300)
                      : const Color(0x3805192D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: displayQty <= 0
                    ? AppTheme.danger.withValues(alpha: 0.6)
                    : displayQty <= _lowStockThreshold
                        ? AppTheme.warning.withValues(alpha: 0.6)
                        : AppTheme.glassBorder,
                width: displayQty <= 0 || displayQty <= _lowStockThreshold
                    ? 1.5
                    : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: displayQty <= 0
                      ? AppTheme.danger.withValues(alpha: 0.15)
                      : displayQty <= _lowStockThreshold
                          ? AppTheme.warning.withValues(alpha: 0.12)
                          : AppTheme.primary.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _showProductDetails(product),
                splashColor: AppTheme.primary.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: stockColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: stockColor.withValues(alpha: 0.25)),
                            ),
                            child: fruitType != null
                                ? Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _avatarColor(fruitType.name)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        fruitType.name.isNotEmpty
                                            ? fruitType.name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  )
                                : Icon(
                                    product.quantity <= 0
                                        ? Icons.inventory_2_outlined
                                        : product.quantity <= _lowStockThreshold
                                            ? Icons.warning_amber_rounded
                                            : Icons.inventory_2_outlined,
                                    color: stockColor,
                                    size: 22,
                                  ),
                          ),
                          const Spacer(),
                          if (fruitType != null
                              ? fruitType.code.isNotEmpty
                              : product.productCode.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                fruitType != null
                                    ? fruitType.code
                                    : product.productCode,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.accent),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayTitle,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: stockColor),
                          const SizedBox(width: 4),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${displayQty.toStringAsFixed(0)} $displayUnit',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: stockColor),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _stockLabel(displayQty),
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                color: stockColor.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                      if (isFruit && isCarton && wpc > 0) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.scale_outlined,
                                size: 13, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'الوزن الصافي: ${(displayQty * wpc).toStringAsFixed(1)} كجم',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.accent.withValues(alpha: 0.12),
                              AppTheme.accent.withValues(alpha: 0.04),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.accent.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.monetization_on_outlined,
                                size: 14, color: AppTheme.accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'قيمة المخزون: ${AppUtils.formatNumber(inventoryValue)} $curr',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'Cairo',
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableView() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Column(
            children: [
              _buildTableHeader(),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _filteredProducts.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, color: Colors.white.withValues(alpha: 0.05)),
                  itemBuilder: (context, index) =>
                      _buildTableRow(_filteredProducts[index], index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: const Color(0x1A00E5FF),
      child: const Row(
        children: [
          SizedBox(
              width: 40,
              child: Text('#',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 13))),
          SizedBox(
              width: 100,
              child: Text('الكود',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 13))),
          Expanded(
              child: Text('الاسم',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 13))),
          SizedBox(
              width: 100,
              child: Text('الكمية',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 13),
                  textAlign: TextAlign.center)),
          SizedBox(
              width: 120,
              child: Text('الحالة',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 13),
                  textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(StationProductModel product, int index) {
    final isEven = index % 2 == 0;
    final isFruit = product.itemType == 'fruit' || product.fruitTypeId != null;

    FruitTypeModel? fruitType;
    RawMaterialModel? rawMaterial;
    if (isFruit) {
      fruitType = (product.fruitTypeId != null ? _fruitTypeMap['fruit_${product.fruitTypeId}'] : null) ??
          (product.productCode.isNotEmpty ? _fruitTypeMap['fruit_code_${product.productCode}'] : null) ??
          _fruitTypeMap['fruit_name_${product.productName.trim().toLowerCase()}'];
    } else {
      rawMaterial = (product.rawMaterialId != null ? _rawMaterialMap['material_${product.rawMaterialId}'] : null) ??
          (product.productCode.isNotEmpty ? _rawMaterialMap['material_code_${product.productCode}'] : null) ??
          _rawMaterialMap['material_name_${product.productName.trim().toLowerCase()}'];
    }

    final isCarton = product.unit == 'carton' || fruitType?.latestPurchaseMode == 'carton' || fruitType?.purchaseMode == 'carton';
    final displayUnit = product.unit == 'carton' || product.unit == 'box' || rawMaterial?.unit == 'carton' || rawMaterial?.unit == 'box'
        ? 'كرتونة'
        : (isFruit ? (isCarton ? 'كرتونة' : 'كجم') : (rawMaterial?.unit ?? 'قطعة'));
    final displayQty = _getProductQuantity(product);
    final stockColor = _stockColor(displayQty);
    final displayCode = isFruit
        ? (fruitType != null && fruitType.code.isNotEmpty ? fruitType.code : product.productCode)
        : (rawMaterial != null && rawMaterial.code.isNotEmpty ? rawMaterial.code : product.productCode);
    final displayTitle = isFruit
        ? (fruitType?.name ?? product.productName)
        : (rawMaterial?.name ?? product.productName.replaceAll(' (مادة تعبئة)', ''));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showProductDetails(product),
        child: Container(
          height: 55,
          color: isEven
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text('${index + 1}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 13)),
              ),
              SizedBox(
                width: 100,
                child: displayCode.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(displayCode,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.accent,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo'),
                            overflow: TextOverflow.ellipsis),
                      )
                    : const Text('—',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 13)),
              ),
              Expanded(
                child: Text(
                    displayTitle,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(
                width: 100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, size: 8, color: stockColor),
                    Text(
                      '${displayQty.toStringAsFixed(0)} $displayUnit',
                      style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: stockColor),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_stockLabel(displayQty),
                        style: TextStyle(
                            color: stockColor,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _avatarColor(String name) {
    final colors = [
      AppTheme.primary,
      AppTheme.accent,
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFFF97316),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  void _showProductDetails(StationProductModel product) {
    final isFruit = product.itemType == 'fruit' || product.fruitTypeId != null;
    final pType = isFruit ? 'fruit' : 'material';
    final pKey = product.itemKey;
    final secKey = '${pType}_code_${product.productCode.trim()}';
    final nameKey = '${pType}_name_${product.productName.trim().toLowerCase()}';
    final curr = _productDisplayCurrency[pKey] ??
        (product.productCode.trim().isNotEmpty ? _productDisplayCurrency[secKey] : null) ??
        _productDisplayCurrency[nameKey] ??
        _productCurrency(product.productName);
    final rawMatParam = product.rawMaterialId != null ? '&rawMaterialId=${product.rawMaterialId}' : '';
    final fruitTypeParam = product.fruitTypeId != null ? '&fruitTypeId=${product.fruitTypeId}' : '';
    final itemTypeParam = '&itemType=${product.itemType}';
    context.push(
        '/station-product-details?id=${widget.stationId}&name=${Uri.encodeComponent(widget.stationName)}&code=${Uri.encodeComponent(widget.stationCode)}&type=${widget.stationType}&productName=${Uri.encodeComponent(product.productName)}&productCode=${Uri.encodeComponent(product.productCode)}&quantity=${product.quantity}&currency=$curr$rawMatParam$fruitTypeParam$itemTypeParam')
        .then((_) => _loadData());
  }
}
