import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/dao/station_product_dao.dart';
import '../../data/dao/stock_movement_dao.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/models/station_model.dart';
import '../../data/models/station_product_model.dart';
import '../../data/models/stock_movement_model.dart';

class PackingMaterialTransferPage extends StatefulWidget {
  const PackingMaterialTransferPage({super.key});

  @override
  State<PackingMaterialTransferPage> createState() => _PackingMaterialTransferPageState();
}

class _PackingMaterialTransferPageState extends State<PackingMaterialTransferPage> {
  bool _isReturn = false;

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
            _buildTabBar(),
            Expanded(child: _isReturn ? _MaterialReturnForm() : _MaterialSendForm()),
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
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, bottom: 12, left: 8, right: 8),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            const Text('مواد التعبئة',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ]),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isReturn = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: !_isReturn ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('إرسال مواد', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isReturn = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _isReturn ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('مرتجع مواد', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MaterialSendForm extends StatefulWidget {
  @override
  State<_MaterialSendForm> createState() => _MaterialSendFormState();
}

class _MaterialSendFormState extends State<_MaterialSendForm> {
  final _formKey = GlobalKey<FormState>();
  final _rawMaterialDao = RawMaterialDao();
  final _stationDao = StationDao();
  final _stationProductDao = StationProductDao();
  final _stockMovementDao = StockMovementDao();
  final _quantityCtrl = TextEditingController();

  List<RawMaterialModel> _rawMaterials = [];
  List<StationModel> _packingStations = [];
  String? _selectedProductId;
  int? _selectedPackingStationId;
  double _quantity = 0;
  bool _loading = true;
  bool _diagnosticsExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _rawMaterialDao.getAll(),
        _stationDao.getSubStations(),
      ]);
      if (mounted) {
        final subStations = results[1] as List<StationModel>;

        setState(() {
          _rawMaterials = results[0] as List<RawMaterialModel>;
          _packingStations = subStations;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0x3805192D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('إرسال مواد تعبئة', style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedProductId,
                    decoration: _inputDecoration('المادة'),
                    dropdownColor: const Color(0xFF05192D),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                    items: _rawMaterials.map((p) => DropdownMenuItem<String>(
                      value: p.id,
                      child: Text('${p.name} (المخزون: ${p.quantity})', style: const TextStyle(fontFamily: 'Cairo')),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedProductId = v),
                    validator: (v) => v == null ? 'اختر المادة' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedPackingStationId,
                    decoration: _inputDecoration('مخزن التعبئة الوجهة'),
                    dropdownColor: const Color(0xFF05192D),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                    items: _packingStations.map((s) => DropdownMenuItem<int>(
                      value: int.parse(s.id!),
                      child: Text(s.name, style: const TextStyle(fontFamily: 'Cairo')),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedPackingStationId = v),
                    validator: (v) => v == null ? 'اختر المخزن' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _quantityCtrl,
                    decoration: _inputDecoration('الكمية'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                    onChanged: (v) => _quantity = double.tryParse(v) ?? 0,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'أدخل كمية صحيحة';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('إرسال', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ),
                  if (_rawMaterials.isEmpty) _buildEmptyWarning(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyWarning() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warning.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.warning.withAlpha(40)),
        ),
        child: const Text('لم يتم العثور على مواد تعبئة',
            style: TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final product = _rawMaterials.firstWhere((p) => p.id == _selectedProductId);

    try {
      await _rawMaterialDao.adjustQuantity(_selectedProductId!, -_quantity);

      final stationProductName = '${product.name} (مادة تعبئة)';
      await _stationProductDao.upsertQuantity(
        stationId: _selectedPackingStationId!,
        productName: stationProductName,
        productCode: product.code,
        delta: _quantity,
      );

      await _stockMovementDao.insert(StockMovementModel(
        movementType: 'transfer',
        productId: _selectedProductId!,
        quantity: _quantity,
        description: 'صرف مواد تعبئة: ${product.name} → ${_packingStations.firstWhere((s) => s.id == _selectedPackingStationId).name}',
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال المواد'), backgroundColor: AppTheme.success, duration: Duration(seconds: 2)),
        );
        _quantityCtrl.clear();
        setState(() {
          _selectedProductId = null;
          _selectedPackingStationId = null;
          _quantity = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, fontFamily: 'Cairo'),
      filled: true,
      fillColor: const Color(0x1AFFFFFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

class _MaterialReturnForm extends StatefulWidget {
  @override
  State<_MaterialReturnForm> createState() => _MaterialReturnFormState();
}

class _MaterialReturnFormState extends State<_MaterialReturnForm> {
  final _formKey = GlobalKey<FormState>();
  final _rawMaterialDao = RawMaterialDao();
  final _stationDao = StationDao();
  final _stationProductDao = StationProductDao();
  final _stockMovementDao = StockMovementDao();
  final _quantityCtrl = TextEditingController();

  List<StationModel> _packingStations = [];
  List<StationProductModel> _stationProducts = [];
  int? _selectedPackingStationId;
  int? _selectedStationProductId;
  double _quantity = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final stations = await _stationDao.getSubStations();
      if (mounted) setState(() { _packingStations = stations; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStationProducts(int stationId) async {
    try {
      final products = await _stationProductDao.getByStation(stationId);
      if (mounted) setState(() => _stationProducts = products);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0x3805192D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مرتجع مواد تعبئة', style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _selectedPackingStationId,
                    decoration: _inputDecoration('من مخزن التعبئة'),
                    dropdownColor: const Color(0xFF05192D),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                    items: _packingStations.map((s) => DropdownMenuItem<int>(
                      value: int.parse(s.id!),
                      child: Text(s.name, style: const TextStyle(fontFamily: 'Cairo')),
                    )).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedPackingStationId = v;
                        _selectedStationProductId = null;
                        _stationProducts = [];
                      });
                      if (v != null) _loadStationProducts(v);
                    },
                    validator: (v) => v == null ? 'اختر المخزن' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedStationProductId,
                    decoration: _inputDecoration('المادة'),
                    dropdownColor: const Color(0xFF05192D),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                    items: _stationProducts
                        .where((sp) => sp.quantity > 0)
                        .map((sp) => DropdownMenuItem(
                              value: sp.id,
                              child: Text('${sp.productName} (${sp.quantity.toStringAsFixed(1)})',
                                  style: const TextStyle(fontFamily: 'Cairo')),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedStationProductId = v),
                    validator: (v) => v == null ? 'اختر المادة' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _quantityCtrl,
                    decoration: _inputDecoration('الكمية'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                    onChanged: (v) => _quantity = double.tryParse(v) ?? 0,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'أدخل كمية صحيحة';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('إرجاع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final sp = _stationProducts.firstWhere((p) => p.id == _selectedStationProductId);

    try {
      final allMaterials = await _rawMaterialDao.getAll();
      final product = allMaterials.cast<RawMaterialModel?>().firstWhere(
        (p) => (p?.code.isNotEmpty == true && p?.code == sp.productCode) || p?.name == sp.productName.replaceAll(' (مادة تعبئة)', ''),
        orElse: () => null,
      );

      await _stationProductDao.upsertQuantity(
        stationId: _selectedPackingStationId!,
        productName: sp.productName,
        productCode: sp.productCode,
        delta: -_quantity,
      );

      if (product?.id != null) {
        await _rawMaterialDao.adjustQuantity(product!.id!, _quantity);
      }

      await _stockMovementDao.insert(StockMovementModel(
        movementType: 'return',
        productId: product?.id ?? '0',
        quantity: _quantity,
        description: 'مرتجع مواد تعبئة: ${sp.productName}',
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرجاع المواد'), backgroundColor: AppTheme.success, duration: Duration(seconds: 2)),
        );
        _quantityCtrl.clear();
        setState(() {
          _selectedPackingStationId = null;
          _selectedStationProductId = null;
          _quantity = 0;
          _stationProducts = [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, fontFamily: 'Cairo'),
      filled: true,
      fillColor: const Color(0x1AFFFFFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}
